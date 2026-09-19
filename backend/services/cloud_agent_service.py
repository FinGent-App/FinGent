import os
import logging
from typing import Dict, Any, Optional, List
import google.generativeai as genai
from services.milvus_service import search_knowledge_hybrid
from services.yahoo_service import get_stock_fundamentals, get_single_quote
from services.portfolio_db_service import get_user_holdings
from services.news_db_service import get_news_by_ticker
from services.rss_ingestion_service import extract_tickers, sync_ticker_news, is_idx_ticker, INDONESIAN_SOURCES
from services.agent_tools_service import analyze_portfolio_impact, analyze_news_impact

logger = logging.getLogger("FinGent.CloudAgent")

GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "")
GEMINI_MODEL = os.getenv("GEMINI_MODEL", "models/gemini-3.6-flash")

# Configure Google Generative AI client using REST transport for low latency & reliability
if GEMINI_API_KEY:
    genai.configure(api_key=GEMINI_API_KEY, transport="rest")
    logger.info("✅ Google Gemini Cloud Agent initialized with model: %s", GEMINI_MODEL)
else:
    logger.warning("⚠️ GEMINI_API_KEY not found in environment. Cloud Agent running in fallback mode.")


async def consult_cloud_analyst(
    query: str,
    ticker: Optional[str] = None,
    user_id: str = "default_user"
) -> Dict[str, Any]:
    """
    Executes deep cloud financial research by orchestrating:
    1. Vector Semantic RAG across SEC filings, financial news, and portfolio records (Zilliz Milvus).
    2. Live market valuation and fundamental ratios (Yahoo Finance).
    3. Portfolio exposure calculation (Supabase PostgreSQL).
    4. Multi-modal synthesis via Google Gemini 1.5/3.6 Flash.
    Returns an executive research briefing for the iOS master agent.
    """
    clean_ticker = ticker.strip().upper() if ticker else None
    if not clean_ticker:
        extracted = extract_tickers(query, "")
        if extracted:
            clean_ticker = extracted[0]

    citations = []
    rag_context_lines = []

    # Step 1: Query Zilliz Milvus Vector RAG (SEC filings, News, Portfolio)
    rag_hits = search_knowledge_hybrid(query_text=query, ticker=clean_ticker, user_id=user_id, limit=5)
    
    # Filter out portfolio documents of unrelated tickers when focusing on a specific stock
    for h in rag_hits:
        if clean_ticker and h.get("doc_type") == "portfolio" and h.get("ticker") != clean_ticker:
            continue

        citations.append({
            "id": h.get("id"),
            "title": h.get("title"),
            "doc_type": h.get("doc_type"),
            "badge_label": h.get("badge_label"),
            "source_url": h.get("source_url"),
            "score": round(h.get("score", 0.0), 4),
            "ticker": h.get("ticker")
        })
        rag_context_lines.append(
            f"[{h.get('doc_type', 'DOC').upper()} - {h.get('title')}] (Ticker: {h.get('ticker', 'N/A')})\n"
            f"{h.get('content', '')}"
        )

    # Step 2: Fetch Live Market Fundamentals & Quotes
    market_context = ""
    target_ticker = clean_ticker or (citations[0]["ticker"] if citations and citations[0].get("ticker") not in ["MARKET", "GLOBAL", None] else None)
    if target_ticker and target_ticker not in ["MARKET", "GLOBAL"]:
        try:
            fund = get_stock_fundamentals(target_ticker)
            quote = get_single_quote(target_ticker)
            market_context = (
                f"LIVE MARKET DATA FOR {target_ticker}:\n"
                f"- Name: {fund.get('name', target_ticker)}\n"
                f"- Price: ${quote.get('price', 0.0):.2f} (24h: {quote.get('change_percent', 0.0):+.2f}%)\n"
                f"- Sector: {fund.get('sector', 'N/A')}\n"
                f"- Forward P/E: {fund.get('forward_pe', 'N/A')}\n"
                f"- Trailing P/E: {fund.get('pe_ratio', 'N/A')}\n"
                f"- PBV Ratio: {fund.get('pbv_ratio', 'N/A')}\n"
                f"- EPS: {fund.get('eps', 'N/A')}\n"
                f"- Free Cash Flow: {fund.get('free_cashflow', 'N/A')}\n"
                f"- Market Cap: ${fund.get('market_cap', 0.0):,.0f}\n"
            )
        except Exception as e:
            logger.warning("Failed to fetch live market context for %s: %s", target_ticker, str(e))

    # Step 2.5: Ingest & Retrieve Verified News for Target Ticker
    news_context = ""
    if target_ticker and target_ticker not in ["MARKET", "GLOBAL"]:
        try:
            await sync_ticker_news(target_ticker)
        except Exception as e:
            logger.warning("Failed to sync ticker news for %s: %s", target_ticker, str(e))

        raw_ticker_news = await get_news_by_ticker(target_ticker, limit=10)
        is_idx = is_idx_ticker(target_ticker)
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
            for n in ticker_news:
                news_lines.append(f"• [{n.get('source', 'News')}] {n.get('title')}\n  Ringkasan: {n.get('summary', '')}\n  Link: {n.get('url', '')}")
                # Add to citations for the iOS UI cards
                citations.append({
                    "id": n.get("id"),
                    "title": n.get("title"),
                    "doc_type": "news",
                    "badge_label": f"{n.get('source', 'News')} (RSS)",
                    "source_url": n.get("url"),
                    "score": 1.0,
                    "ticker": target_ticker
                })
            news_context = f"VERIFIED NEWS HEADLINES & CATALYSTS FOR {target_ticker}:\n" + "\n".join(news_lines)

    # Step 3: Fetch User Portfolio Context (Strictly Scoped)
    portfolio_context = ""
    try:
        holdings = await get_user_holdings(user_id)
        if holdings:
            if target_ticker and target_ticker not in ["MARKET", "GLOBAL"]:
                # ONLY inspect holding for this specific stock if the user owns it
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
                # Only include all holdings if the query explicitly asks about the overall portfolio
                lower_q = query.lower()
                portfolio_keywords = ["portofolio", "portfolio", "holding", "semua saham", "aset", "total kekayaan", "alokasi"]
                if any(kw in lower_q for kw in portfolio_keywords):
                    holding_summaries = [
                        f"• {h.get('ticker')}: {h.get('shares')} shares @ avg purchase ${h.get('price_per_share', 0.0):.2f} (Total Invested: ${h.get('invested_amount', 0.0):.2f})"
                        for h in holdings
                    ]
                    portfolio_context = "USER PORTFOLIO HOLDINGS (Supabase PostgreSQL):\n" + "\n".join(holding_summaries)
    except Exception as e:
        logger.warning("Failed to fetch user holdings: %s", str(e))

    # Step 4: Macroeconomic Scenario Evaluation (if query mentions macro risks)
    macro_context = ""
    lower_q = query.lower()
    if any(k in lower_q for k in ["fed", "rate", "bunga", "inflasi", "inflation", "dampak", "impact", "recession", "resesi"]):
        try:
            impact = await analyze_portfolio_impact(user_id=user_id, event=query)
            macro_context = (
                f"MACRO RISK SCENARIO ANALYSIS:\n"
                f"- Scenario: {impact.get('event')}\n"
                f"- Portfolio Exposure: {impact.get('exposure_percent')}%\n"
                f"- Summary: {impact.get('analysis')}\n"
            )
        except Exception as e:
            logger.warning("Macro scenario evaluation failed: %s", str(e))

    # Step 5: Synthesize Research with Gemini Cloud Agent
    system_prompt = (
        "You are the FinGent Senior Wall Street Research Analyst (Cloud Research Agent). "
        "You serve as the specialized cloud research co-pilot for the user's personal investment assistant. "
        "Provide an authoritative, rigorous, objective, and concise financial research briefing in natural, professional Indonesian. "
        "Ground your analysis strictly on the provided factual evidence (Latest News Headlines, Market Valuation, SEC Filings). "
        "CRITICAL RULES FOR STOCK QUERIES:\n"
        "1. When the user asks why a specific stock is rising/falling or its outlook (e.g. Micron / MU):\n"
        "   - Focus PRIMARILY on the latest news headlines, company catalysts, industry developments (e.g. AI HBM memory demand, earnings, guidance), and market momentum for THAT specific stock.\n"
        "   - If the user holds that specific stock, you may briefly relate the catalyst to their position in that stock.\n"
        "   - STRICTLY FORBIDDEN: Do NOT mention, assume, or read other unrelated portfolio holdings (such as AAPL, BBCA, etc.). They have no relevance to this inquiry.\n"
        "2. Do not hallucinate or invent numbers. Clearly cite news headlines or SEC filings when making statements.\n"
        "Keep the output structured with sections: Ringkasan Utama, Katalis Berita & Analisis Finansial, dan Implikasi Strategis bagi Investor."
    )

    combined_evidence = []
    if news_context:
        combined_evidence.append(news_context)
    if market_context:
        combined_evidence.append(market_context)
    if portfolio_context:
        combined_evidence.append(portfolio_context)
    if macro_context:
        combined_evidence.append(macro_context)
    if rag_context_lines:
        combined_evidence.append("REGULATORY SEC FILINGS & FACTUAL EVIDENCE (Zilliz Milvus RAG):\n" + "\n---\n".join(rag_context_lines))

    evidence_text = "\n\n".join(combined_evidence) if combined_evidence else "No external documents found in database."

    full_prompt = (
        f"{system_prompt}\n\n"
        f"=== FACTUAL GROUNDING CONTEXT ===\n"
        f"{evidence_text}\n"
        f"=================================\n\n"
        f"RESEARCH QUESTION: {query}\n\n"
        f"ANALYST BRIEFING:"
    )

    # Invoke Gemini 3.6/1.5 Flash
    analyst_report = ""
    used_model = GEMINI_MODEL
    try:
        model = genai.GenerativeModel(GEMINI_MODEL)
        resp = model.generate_content(full_prompt)
        analyst_report = resp.text.strip()
    except Exception as e:
        logger.error("Gemini Cloud Agent generation failed: %s. Falling back to structured evidence.", str(e))
        # Deterministic fallback so the system remains resilient
        used_model = "Deterministic-Analyst-Fallback"
        analyst_report = (
            f"**Executive Research Summary for '{query}'**\n\n"
            f"{market_context}\n"
            f"**Regulatory & News Evidence Found:**\n"
            + "\n".join([f"- {c['title']} ({c['doc_type'].upper()}): {c['source_url']}" for c in citations[:3]])
            + f"\n\n**Analyst Note:** Based on available SEC and market filings, review valuation multiples against target sector peers."
        )

    return {
        "query": query,
        "ticker": target_ticker,
        "analyst_report": analyst_report,
        "citations": citations,
        "model": used_model
    }
