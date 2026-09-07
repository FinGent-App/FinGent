import logging
from typing import List, Dict, Any, Optional
from services.yahoo_service import (
    get_single_quote,
    get_batch_quotes,
    get_stock_fundamentals,
    get_market_summary
)
from services.news_db_service import get_recent_news, get_news_by_ticker
from services.portfolio_db_service import get_user_holdings
from services.milvus_service import search_knowledge_hybrid

logger = logging.getLogger("FinGent.AgentTools")


# ==============================================================================
# 1. Market Movers Tool
# ==============================================================================

def get_market_movers(mover_type: str = "gainers") -> Dict[str, Any]:
    """
    Retrieves top market gainers, losers, or benchmark performance.
    """
    summary = get_market_summary()
    stocks = summary.get("popular_stocks", summary.get("stocks", []))
    clean_type = mover_type.lower().strip()

    if clean_type == "losers":
        sorted_stocks = sorted(stocks, key=lambda s: s.get("change_percent", 0.0))
        title = "Top Losers"
    else:
        sorted_stocks = sorted(stocks, key=lambda s: s.get("change_percent", 0.0), reverse=True)
        title = "Top Gainers"

    return {
        "title": title,
        "index": summary.get("ihsg", summary.get("index", {})),
        "count": len(sorted_stocks),
        "movers": sorted_stocks[:10]
    }


# ==============================================================================
# 2. Stock Fundamentals Tool
# ==============================================================================

def get_stock_fundamentals_tool(ticker: str) -> Dict[str, Any]:
    """
    Retrieves key fundamental metrics (P/E, PBV, ROE, Market Cap, Dividend Yield).
    """
    clean_ticker = ticker.strip().upper()
    return get_stock_fundamentals(clean_ticker)


# ==============================================================================
# 3. Compare Stocks Tool
# ==============================================================================

def compare_stocks(tickers: List[str]) -> Dict[str, Any]:
    """
    Compares two or more stocks side-by-side on price, valuation ratios, and returns.
    """
    clean_tickers = [t.strip().upper() for t in tickers if t.strip()]
    if len(clean_tickers) < 2:
        return {"error": "Please provide at least 2 stock tickers for comparison."}

    quotes_list = get_batch_quotes(clean_tickers)
    quotes_map = {q.get("ticker"): q for q in quotes_list if isinstance(q, dict)}
    comparison = []

    for t in clean_tickers:
        quote = quotes_map.get(t, {})
        try:
            fund = get_stock_fundamentals(t)
        except Exception:
            fund = {}

        comparison.append({
            "ticker": t,
            "name": quote.get("name", fund.get("name", t)),
            "price": quote.get("price", 0.0),
            "change_percent": quote.get("change_percent", 0.0),
            "sector": fund.get("sector", "N/A"),
            "pe_ratio": fund.get("pe_ratio", 0.0),
            "pbv_ratio": fund.get("pbv_ratio", 0.0),
            "roe": fund.get("roe", 0.0),
            "market_cap": fund.get("market_cap", 0.0),
            "dividend_yield": fund.get("dividend_yield", 0.0)
        })

    return {
        "tickers": clean_tickers,
        "count": len(comparison),
        "comparison": comparison
    }


# ==============================================================================
# 4. Latest News Tool
# ==============================================================================

async def get_latest_news(count: int = 5) -> List[Dict[str, Any]]:
    """
    Retrieves latest financial news articles from Supabase PostgreSQL.
    """
    return await get_recent_news(limit=count)


# ==============================================================================
# 5. Search Market News Tool (Semantic RAG)
# ==============================================================================

def search_market_news(query: str, limit: int = 5) -> List[Dict[str, Any]]:
    """
    Performs dense vector semantic search across news and documents via Zilliz Milvus.
    """
    return search_knowledge_hybrid(query_text=query, limit=limit)


# ==============================================================================
# 6. Portfolio News Tool
# ==============================================================================

async def get_portfolio_news(user_id: str = "default_user", ticker: Optional[str] = None) -> Dict[str, Any]:
    """
    Retrieves news specifically tailored to the user's portfolio holdings.
    """
    if ticker and ticker.upper() != "ALL":
        clean_ticker = ticker.strip().upper()
        articles = await get_news_by_ticker(clean_ticker, limit=10)
        return {
            "target": clean_ticker,
            "count": len(articles),
            "articles": articles
        }

    holdings = await get_user_holdings(user_id)
    if not holdings:
        fallback_articles = await get_recent_news(limit=10)
        return {
            "target": "all_holdings (empty portfolio)",
            "count": len(fallback_articles),
            "articles": fallback_articles
        }

    tickers = [h.get("ticker", "").upper() for h in holdings if h.get("ticker")]
    all_articles = []
    for t in tickers:
        arts = await get_news_by_ticker(t, limit=4)
        all_articles.extend(arts)

    # Deduplicate by ID
    unique_articles = {a["id"]: a for a in all_articles}.values()
    sorted_unique = sorted(unique_articles, key=lambda a: a.get("published_at", ""), reverse=True)

    return {
        "target": "portfolio_holdings",
        "tickers": tickers,
        "count": len(sorted_unique),
        "articles": list(sorted_unique)[:15]
    }


# ==============================================================================
# 7. Analyze News Impact Tool
# ==============================================================================

async def analyze_news_impact(topic_or_headline: str) -> Dict[str, Any]:
    """
    Analyzes how a news topic or catalyst affects related stocks.
    """
    # 1. Search semantic matches in Zilliz Milvus RAG
    hits = search_knowledge_hybrid(query_text=topic_or_headline, limit=4)

    # Extract detected tickers
    detected_tickers = set()
    for h in hits:
        t = h.get("ticker")
        if t and t not in ["MARKET", "GLOBAL", ""]:
            detected_tickers.add(t)

    # Fallback to topic search in DB if no vector hits
    if not hits:
        recent = await get_recent_news(limit=5)
        articles_context = recent
    else:
        articles_context = hits

    # Fetch live quotes for affected tickers
    affected_quotes = []
    if detected_tickers:
        quotes_list = get_batch_quotes(list(detected_tickers))
        for q in quotes_list:
            if isinstance(q, dict):
                affected_quotes.append({
                    "ticker": q.get("ticker", ""),
                    "name": q.get("name", q.get("ticker", "")),
                    "price": q.get("price", 0.0),
                    "change_percent": q.get("change_percent", 0.0)
                })

    # Determine sentiment score
    topic_lower = topic_or_headline.lower()
    positive_words = ["surge", "soar", "profit", "gain", "growth", "jump", "record", "beat", "dividend", "expand", "naik", "untung"]
    negative_words = ["drop", "fall", "slump", "loss", "plunge", "decline", "warn", "cut", "risk", "turun", "rugi", "inflasi"]

    pos_score = sum(1 for w in positive_words if w in topic_lower)
    neg_score = sum(1 for w in negative_words if w in topic_lower)

    if pos_score > neg_score:
        sentiment = "BULLISH"
    elif neg_score > pos_score:
        sentiment = "BEARISH"
    else:
        sentiment = "NEUTRAL"

    return {
        "topic": topic_or_headline,
        "sentiment": sentiment,
        "affected_stocks": affected_quotes,
        "evidence_articles": articles_context[:3],
        "summary": f"Analisis sentimen pasar untuk topik '{topic_or_headline}' menunjukkan bias {sentiment}. Teridentifikasi {len(affected_quotes)} emiten terkait."
    }


# ==============================================================================
# 8. Analyze Portfolio Impact Tool
# ==============================================================================

async def analyze_portfolio_impact(user_id: str, event: str) -> Dict[str, Any]:
    """
    Analyzes how a macro event or market scenario impacts the user's specific portfolio holdings.
    """
    holdings = await get_user_holdings(user_id)
    if not holdings:
        return {
            "event": event,
            "total_portfolio_value": 0.0,
            "exposure_value": 0.0,
            "exposure_percent": 0.0,
            "affected_holdings": [],
            "analysis": "Portofolio pengguna saat ini masih kosong."
        }

    # Fetch latest quotes to calculate current market values
    tickers = [h.get("ticker", "").upper() for h in holdings if h.get("ticker")]
    quotes_list = get_batch_quotes(tickers)
    quotes_map = {q.get("ticker"): q for q in quotes_list if isinstance(q, dict)}

    total_value = 0.0
    resolved_holdings = []
    for h in holdings:
        t = h.get("ticker", "").upper()
        shares = h.get("shares", 0)
        avg_price = h.get("price_per_share", 0.0)
        current_price = quotes_map.get(t, {}).get("price", avg_price)
        market_val = shares * current_price
        total_value += market_val

        resolved_holdings.append({
            "ticker": t,
            "name": h.get("name", t),
            "sector": h.get("sector", "Other"),
            "shares": shares,
            "market_value": market_val,
            "avg_price": avg_price,
            "current_price": current_price
        })

    # Evaluate event keywords to find affected sectors
    event_lower = event.lower()
    affected_list = []

    for h in resolved_holdings:
        sector_lower = h["sector"].lower()
        reason = None

        if "rate" in event_lower or "bunga" in event_lower or "fed" in event_lower or "bi" in event_lower:
            if "financial" in sector_lower or "bank" in sector_lower:
                reason = "Sektor perbankan terpengaruh langsung oleh Net Interest Margin (NIM) dan likuiditas kredit."
            elif "tech" in sector_lower:
                reason = "Sektor teknologi sensitif terhadap kenaikan suku bunga terkait beban diskonto valuasi masa depan."
        elif "inflation" in event_lower or "inflasi" in event_lower:
            if "consumer" in sector_lower:
                reason = "Daya beli konsumen dan margin laba barang konsumsi tertekan inflasi."
            elif "commodity" in sector_lower or "energy" in sector_lower:
                reason = "Komoditas dan energi sering menjadi lindung nilai alami terhadap inflasi."
        elif "dollar" in event_lower or "usd" in event_lower or "rupiah" in event_lower:
            if "tech" in sector_lower or "chip" in sector_lower or "semi" in sector_lower:
                reason = "Saham berdenominasi USD (AS) menguat nilainya terhadap Rupiah saat USD menguat."

        if not reason and ("chip" in event_lower or "ai" in event_lower):
            if "semi" in sector_lower or "tech" in sector_lower:
                reason = "Permintaan semikonduktor dan server akselerator AI berdampak langsung pada pendapatan."

        if reason:
            weight = (h["market_value"] / total_value * 100) if total_value > 0 else 0.0
            affected_list.append({
                "ticker": h["ticker"],
                "name": h["name"],
                "sector": h["sector"],
                "market_value": h["market_value"],
                "portfolio_weight": round(weight, 1),
                "reason": reason
            })

    affected_value = sum(item["market_value"] for item in affected_list)
    exposure_pct = (affected_value / total_value * 100) if total_value > 0 else 0.0

    return {
        "event": event,
        "total_portfolio_value": round(total_value, 2),
        "exposure_value": round(affected_value, 2),
        "exposure_percent": round(exposure_pct, 1),
        "affected_holdings": affected_list,
        "analysis": f"Skenario '{event}' memengaruhi sekitar {exposure_pct:.1f}% dari total portofolio Anda ({len(affected_list)} emiten terdampak)."
    }
