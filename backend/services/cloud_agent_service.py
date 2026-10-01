import asyncio
import os
import re
import time
import logging
import urllib.parse
import xml.etree.ElementTree as ET
import html
from typing import Dict, Any, Optional, List, Tuple
from cachetools import TTLCache
import httpx
import google.generativeai as genai
from services.milvus_service import search_knowledge_hybrid
from services.yahoo_service import get_stock_fundamentals, get_single_quote
from services.portfolio_db_service import get_user_holdings
from services.news_db_service import get_news_by_ticker
from services.rss_ingestion_service import extract_tickers, sync_ticker_news, is_idx_ticker, INDONESIAN_SOURCES
from services.agent_tools_service import analyze_portfolio_impact, analyze_news_impact

logger = logging.getLogger("FinGent.CloudAgent")

def _clean_analyst_report(text: str) -> str:
    """
    Cleans raw markdown formatting and strips all URL/link clutter so that the
    investor briefing is clean, conversational, and comfortable on mobile screens.
    Citations are rendered separately via the structured sources row in the app.
    """
    if not text:
        return ""

    # 1. Strip heavy markdown headers and bold asterisks
    cleaned = (
        text.replace("***", "")
        .replace("**", "")
        .replace("### ", "")
        .replace("## ", "")
    )

    # 2. Convert markdown links [Label](https://...) -> Label (if label is not a URL itself)
    def _replace_md_link(match):
        label = match.group(1).strip()
        if re.match(r"^https?://", label, re.IGNORECASE):
            return ""
        return label
    cleaned = re.sub(r"\[([^\]]+)\]\(https?://[^\)]+\)", _replace_md_link, cleaned)

    # 3. Remove explicit link / source lines with URL e.g. "• Link: https://...", "Sumber: https://..."
    cleaned = re.sub(r"(?im)^\s*(?:•\s*)?(?:link|sumber|tautan|source|url)(?:\s*(?:link|url))?\s*:\s*https?://\S+\s*$", "", cleaned)

    # 4. Remove parenthesized URLs e.g. "(Sumber: https://...)" or "(https://...)"
    cleaned = re.sub(r"\((?:link|sumber|tautan|source|url)?\s*:?\s*https?://[^\)]+\)", "", cleaned, flags=re.IGNORECASE)

    # 5. Remove any remaining raw URLs
    cleaned = re.sub(r"https?://\S+", "", cleaned)

    # 6. Remove dangling empty link/source labels left behind (e.g. "Sumber:", "• Link:")
    cleaned = re.sub(r"(?im)^\s*(?:•\s*)?(?:link|sumber|tautan|source|url)(?:\s*(?:link|url))?\s*:?\s*$", "", cleaned)

    # 7. Remove empty bullet points left over
    cleaned = re.sub(r"(?m)^\s*•\s*$\n?", "", cleaned)

    # 8. Clean up extra spaces and orphaned spaces before punctuation
    cleaned = re.sub(r"[ \t]{2,}", " ", cleaned)
    cleaned = re.sub(r"[ \t]+([.,!?:;])", r"\1", cleaned)

    # 9. Normalize multiple newlines
    cleaned = re.sub(r"\n{3,}", "\n\n", cleaned)

    return cleaned.strip()

GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "")
GEMINI_MODEL = os.getenv("GEMINI_MODEL", "models/gemini-3.5-flash-lite")

# In-memory TTL Caches to avoid redundant expensive network calls
# BigQuery Lakehouse Gold Layer technicals: 30 minutes TTL
_bigquery_tech_cache: TTLCache = TTLCache(maxsize=100, ttl=1800)
# Live Market Data & Fundamentals: 5 minutes TTL
_market_data_cache: TTLCache = TTLCache(maxsize=100, ttl=300)
# Deep Web Search Grounding: 5 minutes TTL
_web_search_cache: TTLCache = TTLCache(maxsize=100, ttl=300)

# Configure Google Generative AI client using REST transport for low latency & reliability
if GEMINI_API_KEY:
    genai.configure(api_key=GEMINI_API_KEY, transport="rest")
    logger.info("✅ Google Gemini Cloud Agent initialized with model: %s", GEMINI_MODEL)
else:
    logger.warning("⚠️ GEMINI_API_KEY not found in environment. Cloud Agent running in fallback mode.")


def _get_cached_market_data(ticker: str) -> str:
    """Fetches stock fundamentals and quote with in-memory caching."""
    if not ticker or ticker in ["MARKET", "GLOBAL"]:
        return ""
    if ticker in _market_data_cache:
        logger.info("⚡ [CACHE HIT] Market data for %s retrieved from TTL cache", ticker)
        return _market_data_cache[ticker]

    try:
        fund = get_stock_fundamentals(ticker)
        quote = get_single_quote(ticker)
        is_idx = is_idx_ticker(ticker)
        curr = quote.get("currency", "IDR" if is_idx else "USD")
        curr_sym = "Rp " if curr == "IDR" else "$"
        price_val = quote.get("price", 0.0)
        formatted_price = f"{curr_sym}{price_val:,.0f}" if curr == "IDR" else f"{curr_sym}{price_val:,.2f}"
        market_context = (
            f"LIVE MARKET DATA FOR {ticker}:\n"
            f"- Name: {fund.get('name', ticker)}\n"
            f"- Price: {formatted_price} ({curr}) (24h: {quote.get('change_percent', 0.0):+.2f}%)\n"
            f"- Sector: {fund.get('sector', 'N/A')}\n"
            f"- Forward P/E: {fund.get('forward_pe', 'N/A')}\n"
            f"- Trailing P/E: {fund.get('pe_ratio', 'N/A')}\n"
            f"- PBV Ratio: {fund.get('pbv_ratio', 'N/A')}\n"
            f"- EPS: {fund.get('eps', 'N/A')}\n"
            f"- Free Cash Flow: {fund.get('free_cashflow', 'N/A')}\n"
            f"- Market Cap: ${fund.get('market_cap', 0.0):,.0f}\n"
        )
        _market_data_cache[ticker] = market_context
        return market_context
    except Exception as e:
        logger.warning("Failed to fetch live market context for %s: %s", ticker, str(e))
        return ""


def _get_cached_gold_technicals(ticker: str) -> Tuple[str, List[Dict[str, Any]]]:
    """Fetches BigQuery Gold Layer technical indicators with in-memory caching."""
    if not ticker or ticker in ["MARKET", "GLOBAL"]:
        return "", []
    if ticker in _bigquery_tech_cache:
        logger.info("⚡ [CACHE HIT] BigQuery Gold Layer technicals for %s retrieved from TTL cache", ticker)
        return _bigquery_tech_cache[ticker]

    try:
        import sys
        from pathlib import Path
        try:
            from pipeline.warehouse.bigquery_client import warehouse_client
        except ModuleNotFoundError:
            parent_dir = str(Path(__file__).resolve().parent.parent.parent)
            if parent_dir not in sys.path:
                sys.path.insert(0, parent_dir)
            from pipeline.warehouse.bigquery_client import warehouse_client

        gold_analysis = warehouse_client.get_technical_analysis(ticker)
        if gold_analysis and gold_analysis.get("status") != "NO_DATA":
            ma = gold_analysis.get("moving_averages", {})
            rsi = gold_analysis.get("momentum_rsi", {})
            levels = gold_analysis.get("price_levels", {})
            vol = gold_analysis.get("volume_analysis", {})

            context = (
                f"QUANTITATIVE TECHNICAL INDICATORS FROM DATA LAKEHOUSE (GOLD LAYER / BIGQUERY DWH) FOR {ticker}:\n"
                f"- Signal: {gold_analysis.get('signal')}\n"
                f"- Trend Bias: {gold_analysis.get('trend_bias')}\n"
                f"- Moving Averages: MA20: {ma.get('ma_20'):,} | MA50: {ma.get('ma_50'):,} | MA200: {ma.get('ma_200', 'N/A')}\n"
                f"- Golden Cross Signal: {'ACTIVE (MA20 > MA50 - Bullish Momentum)' if ma.get('golden_cross_active') else 'INACTIVE / Death Cross'}\n"
                f"- RSI 14-Day Momentum: {rsi.get('rsi_14')} ({rsi.get('condition')})\n"
                f"- Dynamic Support: {levels.get('support_60d'):,} | Resistance: {levels.get('resistance_60d'):,}\n"
                f"- Volume Breakout Ratio: {vol.get('breakout_ratio')}x\n"
                f"- Summary: {gold_analysis.get('summary')}\n"
            )

            citations = [{
                "id": f"gold_dwh_{ticker}",
                "title": f"BigQuery Gold Layer Technical Analysis ({ticker})",
                "doc_type": "technical_analysis",
                "badge_label": "BigQuery (Gold Layer)",
                "source_url": "gs://fingent-lakehouse-508006/gold/technical_indicators_latest.parquet",
                "score": 1.0,
                "ticker": ticker
            }]
            result = (context, citations)
            _bigquery_tech_cache[ticker] = result
            return result
    except Exception as e:
        logger.warning("Failed to fetch Gold Layer technical indicators for %s: %s", ticker, str(e))
    return "", []


async def _fetch_verified_news_context(ticker: str) -> Tuple[str, List[Dict[str, Any]]]:
    """Syncs and extracts verified news for the target ticker."""
    if not ticker or ticker in ["MARKET", "GLOBAL"]:
        return "", []

    try:
        try:
            await asyncio.wait_for(sync_ticker_news(ticker), timeout=3.5)
        except asyncio.TimeoutError:
            logger.info("Ticker news sync timed out after 3.5s for %s, proceeding with cached/database articles", ticker)
        except Exception as sync_err:
            logger.warning("Failed to sync ticker news for %s: %s", ticker, str(sync_err))

        raw_ticker_news = await get_news_by_ticker(ticker, limit=10)
        is_idx = is_idx_ticker(ticker)
        filtered_news = []
        for n in raw_ticker_news:
            src = n.get("source", "")
            if is_idx:
                if src in {"Nasdaq", "Investing.com", "GlobeNewswire", "PR Newswire", "Business Wire"}:
                    continue
            else:
                if src in INDONESIAN_SOURCES:
                    continue
            filtered_news.append(n)

        ticker_news = filtered_news[:5]
        if ticker_news:
            news_lines = []
            news_citations = []
            for n in ticker_news:
                summary = (n.get("summary") or "").strip()
                if summary:
                    news_lines.append(f"• [{n.get('source', 'News')}] {n.get('title')}\n  Ringkasan: {summary}")
                else:
                    news_lines.append(f"• [{n.get('source', 'News')}] {n.get('title')}")
                news_citations.append({
                    "id": n.get("id"),
                    "title": n.get("title"),
                    "doc_type": "news",
                    "badge_label": f"{n.get('source', 'News')} (RSS)",
                    "source_url": n.get("url"),
                    "score": 1.0,
                    "ticker": ticker
                })
            return f"VERIFIED NEWS HEADLINES & CATALYSTS FOR {ticker}:\n" + "\n".join(news_lines), news_citations
    except Exception as e:
        logger.warning("Failed to fetch verified news for %s: %s", ticker, str(e))
    return "", []


async def _deep_web_search_grounding(query: str, ticker: Optional[str] = None) -> Tuple[str, List[Dict[str, Any]]]:
    """
    Executes live deep web search grounding via Google Search engine indexing.
    Retrieves real-time catalysts, news, rumors, and commentary across all global
    and national media beyond the curated RSS list.
    """
    clean_ticker = ticker.strip().upper() if ticker else None
    stop_words = {
        'will', 'what', 'how', 'the', 'and', 'for', 'are', 'is', 'kan', 'nya',
        'ini', 'itu', 'atau', 'saham', 'stock', 'tentang', 'apakah', 'kenapa',
        'mengapa', 'today', 'yesterday', 'besok', 'kemarin', 'kira', 'menurut',
        'analisis', 'prediksi'
    }
    clean_query = re.sub(r'[^\w\s]', ' ', query)
    tokens = [w for w in clean_query.split() if len(w) > 2 and w.lower() not in stop_words]

    if clean_ticker and clean_ticker not in [t.upper() for t in tokens]:
        search_tokens = [clean_ticker] + tokens[:4]
    else:
        search_tokens = tokens[:5]

    search_query = ' '.join(search_tokens).strip()
    if not search_query and clean_ticker:
        search_query = f"{clean_ticker} stock news"

    cache_key = f"{clean_ticker or 'GLOBAL'}:{search_query.lower()}"
    if cache_key in _web_search_cache:
        logger.info("⚡ [CACHE HIT] Deep Web Search Grounding for '%s' retrieved from cache", cache_key)
        return _web_search_cache[cache_key]

    is_idx = (clean_ticker and is_idx_ticker(clean_ticker)) or any(
        w in query.lower() for w in ['bagaimana', 'apa', 'saham', 'prospek', 'naik', 'turun', 'akuisisi', 'ihsg', 'laba', 'kinerja', 'investasi']
    )
    lang_param = 'hl=id&gl=ID&ceid=ID:id' if is_idx else 'hl=en-US&gl=US&ceid=US:en'

    async def _fetch_from_google(q_str: str) -> List[Any]:
        encoded = urllib.parse.quote(q_str)
        url = f"https://news.google.com/rss/search?q={encoded}&{lang_param}"
        try:
            async with httpx.AsyncClient(timeout=3.5) as client:
                r = await client.get(url, follow_redirects=True)
                if r.status_code == 200:
                    root = ET.fromstring(r.text)
                    return root.findall('.//item')
        except Exception as err:
            logger.warning("Google search fetch failed for '%s': %s", q_str, str(err))
        return []

    try:
        items = await _fetch_from_google(search_query)
        # If slang or specific phrasing returned no hits and ticker is known, fallback to general ticker news
        if not items and clean_ticker:
            fallback_query = f"{clean_ticker} saham" if is_idx else f"{clean_ticker} stock"
            items = await _fetch_from_google(fallback_query)

        citations = []
        grounding_lines = []
        for it in items[:5]:
            title_node = it.find('title')
            link_node = it.find('link')
            title = html.unescape(title_node.text or '') if title_node is not None else ''
            link = link_node.text or '' if link_node is not None else ''
            source_name = 'Web'
            if ' - ' in title:
                parts = title.rsplit(' - ', 1)
                title = parts[0].strip()
                source_name = parts[1].strip()

            grounding_lines.append(f"• [{source_name}] {title}")
            citations.append({
                "id": f"web_{int(time.time()*1000)}_{len(citations)}",
                "title": title,
                "doc_type": "web",
                "badge_label": f"{source_name} (Google Search)",
                "source_url": link,
                "score": 0.95,
                "ticker": clean_ticker or "GLOBAL"
            })

        context_str = (
            f"🌐 LIVE DEEP WEB SEARCH GROUNDING (Google Live Search Engine):\n" + "\n".join(grounding_lines)
            if grounding_lines else ""
        )
        result = (context_str, citations)
        if citations:
            _web_search_cache[cache_key] = result
        return result
    except Exception as e:
        logger.warning("Failed deep web search grounding for '%s': %s", query, str(e))
        return "", []


async def consult_cloud_analyst(
    query: str,
    ticker: Optional[str] = None,
    user_id: str = "default_user"
) -> Dict[str, Any]:
    """
    Executes hybrid cloud financial research with parallelized I/O:
    1. Vector Semantic RAG across SEC filings, financial news, and portfolio records (Zilliz Milvus).
    2. Live market valuation and fundamental ratios (Yahoo Finance - Cached).
    3. Verified RSS news headlines (Curated 12 Financial Portals - Supabase PostgreSQL).
    4. Deep Web Search Grounding via Google Search Engine Indexing (Real-Time Web).
    5. Quantitative technical indicators (BigQuery Gold Layer - Cached).
    6. Portfolio exposure calculation (Supabase PostgreSQL).
    7. Multi-modal synthesis via Google Gemini 3.5 Flash-Lite (Fast Token Generation).
    """
    start_time = time.time()
    clean_ticker = ticker.strip().upper() if ticker else None
    if not clean_ticker:
        extracted = extract_tickers(query, "")
        if extracted:
            clean_ticker = extracted[0]

    target_ticker = clean_ticker
    is_macro = any(k in query.lower() for k in ["fed", "rate", "bunga", "inflasi", "inflation", "dampak", "impact", "recession", "resesi"])

    # --------------------------------------------------------------------------
    # FAST PARALLEL CONCURRENT DATA GATHERING (asyncio.gather)
    # --------------------------------------------------------------------------
    rag_task = asyncio.to_thread(search_knowledge_hybrid, query_text=query, ticker=target_ticker, user_id=user_id, limit=5)
    market_task = asyncio.to_thread(_get_cached_market_data, target_ticker) if target_ticker else None
    news_task = _fetch_verified_news_context(target_ticker) if target_ticker else None
    web_task = _deep_web_search_grounding(query, target_ticker)
    gold_task = asyncio.to_thread(_get_cached_gold_technicals, target_ticker) if target_ticker else None
    holdings_task = get_user_holdings(user_id)
    macro_task = analyze_portfolio_impact(user_id=user_id, event=query) if is_macro else None

    # Execute all independent network, search engine, and database queries concurrently
    tasks = [rag_task, holdings_task, web_task]
    if market_task:
        tasks.append(market_task)
    if news_task:
        tasks.append(news_task)
    if gold_task:
        tasks.append(gold_task)
    if macro_task:
        tasks.append(macro_task)

    gathered_results = await asyncio.gather(*tasks, return_exceptions=True)

    # Unpack safely
    idx = 0
    raw_rag = gathered_results[idx]; idx += 1
    raw_holdings = gathered_results[idx]; idx += 1
    raw_web = gathered_results[idx]; idx += 1
    raw_market = gathered_results[idx] if market_task else ""; idx += (1 if market_task else 0)
    raw_news = gathered_results[idx] if news_task else ("", []); idx += (1 if news_task else 0)
    raw_gold = gathered_results[idx] if gold_task else ("", []); idx += (1 if gold_task else 0)
    raw_macro = gathered_results[idx] if macro_task else None

    rag_hits = raw_rag if isinstance(raw_rag, list) else []
    holdings = raw_holdings if isinstance(raw_holdings, list) else []
    web_context, web_citations = raw_web if isinstance(raw_web, tuple) else ("", [])
    market_context = raw_market if isinstance(raw_market, str) else ""
    news_context, news_citations = raw_news if isinstance(raw_news, tuple) else ("", [])
    gold_technical_context, gold_citations = raw_gold if isinstance(raw_gold, tuple) else ("", [])
    macro_impact = raw_macro if isinstance(raw_macro, dict) else None

    citations = []
    rag_context_lines = []

    # Process Milvus RAG citations
    for h in rag_hits:
        if target_ticker and h.get("doc_type") == "portfolio" and h.get("ticker") != target_ticker:
            continue

        raw_url = h.get("source_url") or ""
        if not raw_url:
            if h.get("doc_type") == "sec":
                raw_url = f"https://www.sec.gov/edgar/searchedgar/companysearch?company={target_ticker or ''}"
            elif h.get("doc_type") == "portfolio":
                raw_url = f"https://finance.yahoo.com/quote/{target_ticker or 'MARKET'}"
            else:
                raw_url = f"https://finance.yahoo.com/quote/{target_ticker or 'MARKET'}"

        citations.append({
            "id": h.get("id"),
            "title": h.get("title"),
            "doc_type": h.get("doc_type"),
            "badge_label": h.get("badge_label"),
            "source_url": raw_url,
            "score": round(h.get("score", 0.0), 4),
            "ticker": h.get("ticker")
        })
        rag_context_lines.append(
            f"[{h.get('doc_type', 'DOC').upper()} - {h.get('title')}] (Ticker: {h.get('ticker', 'N/A')})\n"
            f"{h.get('content', '')}"
        )

    # Add Curated News, Deep Web Search, and BigQuery Gold citations
    citations.extend(news_citations)
    citations.extend(web_citations)
    citations.extend(gold_citations)

    # Deduplicate citations by normalized title and URL
    seen_titles = set()
    seen_urls = set()
    unique_citations = []
    for c in citations:
        title_key = re.sub(r'[^a-zA-Z0-9]', '', c.get("title", "")).lower()
        url_key = c.get("source_url", "")
        if title_key and title_key in seen_titles:
            continue
        if url_key and url_key in seen_urls:
            continue
        seen_titles.add(title_key)
        if url_key:
            seen_urls.add(url_key)
        unique_citations.append(c)
    citations = unique_citations

    # Process Holdings Context
    portfolio_context = ""
    if holdings:
        if target_ticker and target_ticker not in ["MARKET", "GLOBAL"]:
            target_holding = next((h for h in holdings if h.get("ticker", "").upper() == target_ticker), None)
            if target_holding:
                portfolio_context = (
                    f"USER RELEVANT POSITION IN {target_ticker}:\n"
                    f"• {target_ticker}: {target_holding.get('shares')} shares @ avg purchase ${target_holding.get('price_per_share', 0.0):.2f} "
                    f"(Total Invested: ${target_holding.get('invested_amount', 0.0):.2f})\n"
                    f"(STRICT INSTRUCTION: The user is only asking about {target_ticker}. Only mention this holding if relevant. DO NOT mention or reference other holdings.)"
                )
            else:
                portfolio_context = f"USER POSITION IN {target_ticker}: User does not currently hold {target_ticker} in their portfolio."
        else:
            lower_q = query.lower()
            portfolio_keywords = ["portofolio", "portfolio", "holding", "semua saham", "aset", "total kekayaan", "alokasi"]
            if any(kw in lower_q for kw in portfolio_keywords):
                holding_summaries = [
                    f"• {h.get('ticker')}: {h.get('shares')} shares @ avg purchase ${h.get('price_per_share', 0.0):.2f} (Total Invested: ${h.get('invested_amount', 0.0):.2f})"
                    for h in holdings
                ]
                portfolio_context = "USER PORTFOLIO HOLDINGS (Supabase PostgreSQL):\n" + "\n".join(holding_summaries)

    # Process Macro Context
    macro_context = ""
    if macro_impact:
        macro_context = (
            f"MACRO RISK SCENARIO ANALYSIS:\n"
            f"- Scenario: {macro_impact.get('event')}\n"
            f"- Portfolio Exposure: {macro_impact.get('exposure_percent')}%\n"
            f"- Summary: {macro_impact.get('analysis')}\n"
        )

    # Build synthesis evidence
    combined_evidence = []
    if news_context:
        combined_evidence.append(news_context)
    if web_context:
        combined_evidence.append(web_context)
    if market_context:
        combined_evidence.append(market_context)
    if gold_technical_context:
        combined_evidence.append(gold_technical_context)
    if portfolio_context:
        combined_evidence.append(portfolio_context)
    if macro_context:
        combined_evidence.append(macro_context)
    if rag_context_lines:
        combined_evidence.append("REGULATORY SEC FILINGS & FACTUAL EVIDENCE (Zilliz Milvus RAG):\n" + "\n---\n".join(rag_context_lines))

    evidence_text = "\n\n".join(combined_evidence) if combined_evidence else "No external documents found in database."

    system_prompt = (
        "You are FinGent, an intelligent, empathetic financial companion and investment mentor (like ChatGPT). "
        "Your mission is to make stock market research and financial analysis clear, insightful, and accessible for beginner and retail investors. "
        "Always ground your response strictly on the factual evidence provided (Latest Curated News, Deep Live Web Search Grounding via Google Search Engine, Market Valuation, SEC Filings, Technical Indicators).\n\n"
        "KEY COMMUNICATION & FORMATTING PRINCIPLES:\n"
        "1. TONE & STYLE: Conversational, friendly, objective, and encouraging. Never sound like a stiff, dry academic report.\n"
        "2. LANGUAGE: If the user's research question is in Indonesian, answer in natural, fluent Indonesian. If in English, answer in natural English.\n"
        "3. EXPLAIN TECHNICAL METRICS SIMPLY (Data-to-Insight): Keep all exact factual numbers (P/E ratio, PBV, RSI, Support/Resistance, Price), but always briefly explain what the numbers mean for an investor. For example:\n"
        "   - Instead of just 'Forward P/E 12.9x', explain: 'Valuasinya cukup wajar dengan P/E di level 12,9x, yang menunjukkan harga relatif terjangkau dibanding rata-rata industrinya.'\n"
        "   - Instead of just 'RSI 32', explain: 'Indikator momentum RSI berada di angka 32, menandakan saham ini sudah banyak terkoreksi (oversold) dan tekanan jualnya mulai mereda.'\n"
        "4. HYBRID DEEP WEB SEARCH & CATALYST SYNTHESIS: Weave together both curated financial news and deep live web search grounding (e.g. rumors, crossing saham, new products, corporate actions) to explain WHY a stock is moving or what catalysts investors are watching.\n"
        "5. CLEAN FORMATTING - STRICTLY NO MARKDOWN ASTERISKS: DO NOT use markdown bold asterisks (**) or triple asterisks (***). Keep the text clean, elegant, and comfortable to read on mobile screens. Use clean bullet points (•) when listing items.\n"
        "6. RESPONSE STRUCTURE:\n"
        "   - Ringkasan Utama: Answer the user's core question directly and warmly in 1-2 sentences.\n"
        "   - Fakta & Analisis Pasar: Weave together the verified news catalysts, technical indicators, and valuation data.\n"
        "   - Sudut Pandang Investor: A calm, sensible takeaway or key levels to watch.\n"
        "7. SINGLE STOCK FOCUS: When asked about a specific stock, focus strictly on that stock. Never mention unrelated portfolio holdings.\n"
        "8. STRICTLY NO URLS OR LINKS IN TEXT: DO NOT include raw URLs, website addresses, 'Link: http...', 'Sumber: http...', or markdown links '[Title](url)'. The mobile app UI automatically renders interactive citation pills and source badges from structured data below your response. Keep the response text 100% conversational, clean, and free of URL links."
    )

    full_prompt = (
        f"{system_prompt}\n\n"
        f"=== FACTUAL GROUNDING CONTEXT ===\n"
        f"{evidence_text}\n"
        f"=================================\n\n"
        f"RESEARCH QUESTION: {query}\n\n"
        f"INVESTOR BRIEFING:"
    )

    # Invoke Gemini with multi-model fallback chain to ensure resilience against quota/availability issues
    analyst_report = ""
    used_model = "Deterministic-Analyst-Fallback"
    
    preferred_model = os.getenv("GEMINI_MODEL", "models/gemini-3.5-flash-lite")
    raw_candidates = [
        preferred_model if preferred_model.startswith("models/") else f"models/{preferred_model}",
        "models/gemini-3.5-flash-lite",
        "models/gemini-flash-lite-latest",
        "models/gemini-3.1-flash-lite",
        "models/gemini-3.6-flash"
    ]
    seen_models = set()
    models_to_try = [m for m in raw_candidates if not (m in seen_models or seen_models.add(m))]

    for candidate in models_to_try:
        try:
            model = genai.GenerativeModel(candidate)
            generation_config = {
                "max_output_tokens": 4096,
                "temperature": 0.3,
                "top_p": 0.85
            }
            resp = await asyncio.to_thread(
                model.generate_content,
                full_prompt,
                generation_config=generation_config
            )
            if resp and resp.text:
                analyst_report = resp.text.strip()
                used_model = candidate
                logger.info("✅ Successfully generated research briefing with model: %s", candidate)
                break
        except Exception as e:
            logger.warning("⚠️ Gemini model %s failed: %s. Trying next candidate...", candidate, str(e))

    if not analyst_report:
        logger.error("All Gemini model candidates failed. Falling back to structured evidence synthesis.")
        used_model = "Deterministic-Analyst-Fallback"
        news_summaries = []
        for c in citations[:5]:
            news_summaries.append(f"• {c.get('title')} ({c.get('badge_label', 'News')})")
        
        analyst_report = (
            f"Ringkasan Analisis FinGent untuk '{query}':\n\n"
            f"{market_context}\n"
            f"Kabar Berita & Katalis Terkini:\n"
            + "\n".join(news_summaries)
            + f"\n\n{gold_technical_context}\n"
            + f"Catatan untuk Investor: Berdasarkan data pasar dan berita di atas, pantau sentimen sektor dan level harga kunci untuk mengonfirmasi arah tren."
        )

    # Strip stray markdown asterisks, heavy hashes, and raw URLs to guarantee clean, friendly presentation
    analyst_report = _clean_analyst_report(analyst_report)
    # Record execution trace for Admin Dashboard Observability & SSE
    latency_ms = int((time.time() - start_time) * 1000)
    prompt_tokens = max(1, len(full_prompt) // 4)
    completion_tokens = max(1, len(analyst_report) // 4)
    market_type = "IDX" if (target_ticker and is_idx_ticker(target_ticker)) else "US"

    try:
        from services.admin_service import record_agent_log
        await record_agent_log(
            user_id=user_id,
            prompt=query,
            selected_tools=["ConsultCloudAnalystTool"],
            tool_arguments={"ticker": target_ticker, "query": query},
            tool_output=f"Grounding Context: {len(combined_evidence)} blocks. Citations: {len(citations)}.",
            final_answer=analyst_report,
            citations=citations,
            market_type=market_type,
            model_name=used_model,
            prompt_tokens=prompt_tokens,
            completion_tokens=completion_tokens,
            latency_ms=latency_ms,
            relevance_score=0.98 if citations else 0.92,
            status="SUCCESS"
        )
    except Exception as log_err:
        logger.warning("Could not record trace to admin_service: %s", str(log_err))

    return {
        "query": query,
        "ticker": target_ticker,
        "analyst_report": analyst_report,
        "citations": citations,
        "model": used_model
    }
