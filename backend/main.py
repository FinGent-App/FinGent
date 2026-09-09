import logging
from contextlib import asynccontextmanager
from typing import List, Optional
from fastapi import FastAPI, HTTPException, Query, Header
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from database import init_db_pool, close_db_pool, is_connected
from services.yahoo_service import (
    get_single_quote,
    get_batch_quotes,
    get_stock_fundamentals,
    get_market_summary,
    get_stock_history,
    get_sec_filings,
    search_stocks
)
from services.news_db_service import get_news_by_ticker, get_recent_news, get_news_count
from services.rss_ingestion_service import sync_all_rss_feeds, sync_ticker_news
from services.watchlist_db_service import (
    get_user_watchlist,
    add_to_watchlist,
    remove_from_watchlist,
    is_in_watchlist
)
from services.portfolio_db_service import (
    get_user_holdings,
    upsert_holding,
    delete_holding,
    record_transaction,
    get_user_transactions
)
from services.stock_market_db_service import get_or_sync_market_data
from services.milvus_service import (
    search_knowledge_hybrid,
    sync_portfolio_to_milvus,
    sync_sec_to_milvus,
    sync_news_to_milvus
)
from services.agent_tools_service import (
    get_market_movers,
    get_stock_fundamentals_tool,
    compare_stocks,
    get_latest_news as get_agent_latest_news,
    search_market_news as search_agent_market_news,
    get_portfolio_news as get_agent_portfolio_news,
    analyze_news_impact,
    analyze_portfolio_impact
)
from services.cloud_agent_service import consult_cloud_analyst

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
)
logger = logging.getLogger("FinGent.Main")


# ==============================================================================
# FastAPI Lifespan (Clean DB connection management)
# ==============================================================================

@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("🚀 Starting FinGent Backend...")
    await init_db_pool()
    yield
    logger.info("🛑 Shutting down FinGent Backend...")
    await close_db_pool()


app = FastAPI(
    title="FinGent Backend API",
    description="Realtime Stock Data & AI Grounding Service powered by PostgreSQL & Yahoo Finance (Supabase Ready)",
    version="1.1.0",
    lifespan=lifespan
)

# Enable CORS for local development and clients
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ==============================================================================
# Pydantic Request Models
# ==============================================================================

class WatchlistRequest(BaseModel):
    ticker: str = Field(..., description="Stock ticker symbol, e.g. 'MU' or 'BBCA'")
    notes: Optional[str] = Field(None, description="Optional investment notes")


class HoldingRequest(BaseModel):
    ticker: str = Field(..., description="Stock ticker symbol")
    name: str = Field(..., description="Company name")
    shares: int = Field(..., ge=0, description="Total shares owned")
    price_per_share: float = Field(..., gt=0, description="Average purchase price per share")
    invested_amount: float = Field(..., ge=0, description="Total capital invested")
    sector: str = Field("Technology", description="Industry sector")


class TransactionRequest(BaseModel):
    ticker: str = Field(..., description="Stock ticker symbol")
    type: str = Field(..., description="BUY, SELL, or DIVIDEND")
    shares: int = Field(..., gt=0, description="Quantity of shares")
    price_per_share: float = Field(..., gt=0, description="Execution price per share")


class RAGQueryRequest(BaseModel):
    query: str = Field(..., description="User prompt or question")
    ticker: Optional[str] = Field(None, description="Optional stock ticker filter")
    user_id: Optional[str] = Field("default_user", description="User ID for portfolio filtering")
    limit: Optional[int] = Field(5, description="Max knowledge chunks to retrieve")


class CompareStocksRequest(BaseModel):
    tickers: List[str] = Field(..., min_items=2, description="List of stock tickers to compare")


class NewsImpactRequest(BaseModel):
    topic: str = Field(..., description="News topic or headline to evaluate")


class PortfolioImpactRequest(BaseModel):
    event: str = Field(..., description="Macro event or market scenario")
    user_id: Optional[str] = Field("default_user", description="User ID for portfolio lookup")


class ConsultCloudAgentRequest(BaseModel):
    query: str = Field(..., description="Financial, macroeconomic, or SEC research query")
    ticker: Optional[str] = Field(None, description="Optional target stock ticker, e.g. 'MU', 'NVDA'")
    user_id: Optional[str] = Field("default_user", description="User ID for portfolio personalization")


# ==============================================================================
# Health & Status
# ==============================================================================

@app.get("/")
def health_check():
    """Health check endpoint to verify backend and database status."""
    return {
        "status": "online",
        "service": "FinGent Backend API",
        "version": "1.1.0",
        "database": "PostgreSQL (Supabase Ready)" if is_connected() else "Disconnected (Offline Mode)",
        "endpoints": [
            "/api/v1/news?ticker=MU",
            "/api/v1/news/sync",
            "/api/v1/watchlist",
            "/api/v1/portfolio/holdings",
            "/api/v1/stocks/{ticker}",
            "/api/v1/stocks/{ticker}/sec",
            "/api/v1/stocks/batch?tickers=BBCA,TLKM,BBRI",
            "/api/v1/stocks/{ticker}/fundamentals",
            "/api/v1/market/summary",
            "/api/v1/agent/movers",
            "/api/v1/agent/fundamentals/{ticker}",
            "/api/v1/agent/compare",
            "/api/v1/agent/news",
            "/api/v1/agent/news/search",
            "/api/v1/agent/portfolio-news",
            "/api/v1/agent/news-impact",
            "/api/v1/agent/portfolio-impact"
        ]
    }


# ==============================================================================
# News & RSS Grounding Endpoints (PostgreSQL + MCP Tool Ready)
# ==============================================================================

@app.get("/api/v1/news")
async def get_news(
    ticker: Optional[str] = Query(None, description="Stock ticker, e.g. MU, NVDA, BBCA"),
    limit: int = Query(5, ge=1, le=50, description="Maximum number of articles to return"),
    auto_fetch: bool = Query(True, description="Fetch on-demand from RSS if not found in DB")
):
    """
    Retrieves grounded news articles from PostgreSQL.
    If ticker is specified and not enough articles exist in DB, optionally fetches on-demand from RSS feed.
    """
    if not is_connected():
        raise HTTPException(status_code=503, detail="PostgreSQL database is currently unavailable.")

    try:
        if ticker:
            clean_ticker = ticker.strip().upper().replace(".JK", "")
            articles = await get_news_by_ticker(clean_ticker, limit)

            # If empty and auto_fetch enabled, trigger on-demand ticker RSS sync
            if not articles and auto_fetch:
                logger.info("No cached news for %s in DB. Fetching on-demand RSS...", clean_ticker)
                await sync_ticker_news(clean_ticker)
                articles = await get_news_by_ticker(clean_ticker, limit)

            return {
                "ticker": clean_ticker,
                "count": len(articles),
                "articles": articles
            }
        else:
            articles = await get_recent_news(limit)
            return {
                "count": len(articles),
                "articles": articles
            }
    except Exception as e:
        logger.error("Failed to retrieve news: %s", str(e))
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/v1/news/sync")
async def sync_news():
    """
    Triggers an immediate background ingestion of all RSS feeds (Yahoo Finance & CNBC) into PostgreSQL.
    """
    if not is_connected():
        raise HTTPException(status_code=503, detail="PostgreSQL database is currently unavailable.")

    try:
        count = await sync_all_rss_feeds()
        total = await get_news_count()
        return {
            "status": "success",
            "synced_articles": count,
            "total_articles_in_db": total
        }
    except Exception as e:
        logger.error("RSS news sync failed: %s", str(e))
        raise HTTPException(status_code=500, detail=str(e))


# ==============================================================================
# Watchlist / Favorite Stocks Endpoints
# ==============================================================================

@app.get("/api/v1/watchlist")
async def list_watchlist(user_id: str = Query("default_user", description="User ID or device identifier")):
    """
    Returns favorited stock tickers for the given user.
    """
    if not is_connected():
        raise HTTPException(status_code=503, detail="PostgreSQL database is currently unavailable.")
    try:
        items = await get_user_watchlist(user_id)
        return {"user_id": user_id, "count": len(items), "watchlist": items}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/v1/watchlist")
async def add_watchlist(
    body: WatchlistRequest,
    user_id: str = Query("default_user")
):
    """
    Adds or updates a stock ticker in the user's favorites.
    """
    if not is_connected():
        raise HTTPException(status_code=503, detail="PostgreSQL database is currently unavailable.")
    try:
        record = await add_to_watchlist(body.ticker, user_id, body.notes)
        return {"status": "success", "item": record}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.delete("/api/v1/watchlist/{ticker}")
async def remove_watchlist(
    ticker: str,
    user_id: str = Query("default_user")
):
    """
    Removes a stock ticker from user's favorites.
    """
    if not is_connected():
        raise HTTPException(status_code=503, detail="PostgreSQL database is currently unavailable.")
    try:
        deleted = await remove_from_watchlist(ticker, user_id)
        return {"status": "success", "deleted": deleted, "ticker": ticker.upper()}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ==============================================================================
# Portfolio Holdings & Transactions Endpoints
# ==============================================================================

@app.get("/api/v1/portfolio/holdings")
async def list_holdings(user_id: str = Query("default_user")):
    """
    Retrieves the user's active portfolio holdings.
    """
    if not is_connected():
        raise HTTPException(status_code=503, detail="PostgreSQL database is currently unavailable.")
    try:
        holdings = await get_user_holdings(user_id)
        return {"user_id": user_id, "count": len(holdings), "holdings": holdings}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/v1/portfolio/holdings")
async def save_holding(
    body: HoldingRequest,
    user_id: str = Query("default_user")
):
    """
    Creates or updates a holding in the user's portfolio.
    """
    if not is_connected():
        raise HTTPException(status_code=503, detail="PostgreSQL database is currently unavailable.")
    try:
        record = await upsert_holding(
            ticker=body.ticker,
            name=body.name,
            shares=body.shares,
            price_per_share=body.price_per_share,
            invested_amount=body.invested_amount,
            sector=body.sector,
            user_id=user_id
        )
        return {"status": "success", "holding": record}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.delete("/api/v1/portfolio/holdings/{ticker}")
async def delete_user_holding(
    ticker: str,
    user_id: str = Query("default_user")
):
    """
    Deletes a holding from user portfolio.
    """
    if not is_connected():
        raise HTTPException(status_code=503, detail="PostgreSQL database is currently unavailable.")
    try:
        deleted = await delete_holding(ticker, user_id)
        return {"status": "success", "deleted": deleted, "ticker": ticker.upper()}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/v1/portfolio/transactions")
async def create_transaction(
    body: TransactionRequest,
    user_id: str = Query("default_user")
):
    """
    Records a buy or sell transaction.
    """
    if not is_connected():
        raise HTTPException(status_code=503, detail="PostgreSQL database is currently unavailable.")
    try:
        tx = await record_transaction(
            ticker=body.ticker,
            tx_type=body.type,
            shares=body.shares,
            price_per_share=body.price_per_share,
            user_id=user_id
        )
        return {"status": "success", "transaction": tx}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/v1/portfolio/transactions")
async def list_transactions(
    user_id: str = Query("default_user"),
    limit: int = Query(50, ge=1, le=200)
):
    """
    Returns user transaction history.
    """
    if not is_connected():
        raise HTTPException(status_code=503, detail="PostgreSQL database is currently unavailable.")
    try:
        txs = await get_user_transactions(user_id, limit)
        return {"user_id": user_id, "count": len(txs), "transactions": txs}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ==============================================================================
# Existing Yahoo Finance Realtime Stock Endpoints (Preserved 100%)
# ==============================================================================

@app.get("/api/v1/stocks/batch")
def get_batch(
    tickers: str = Query(..., description="Comma-separated stock tickers (e.g. BBCA,TLKM,GOTO)")
):
    """Get quotes for multiple stocks in a single request."""
    ticker_list = [t.strip() for t in tickers.split(",") if t.strip()]
    if not ticker_list:
        raise HTTPException(status_code=400, detail="Parameter 'tickers' must not be empty.")

    try:
        quotes = get_batch_quotes(ticker_list)
        return {"count": len(quotes), "data": quotes}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to fetch batch quotes: {str(e)}")


@app.get("/api/v1/stocks/search")
def search_stocks_endpoint(
    q: str = Query(..., description="Company name, alias, or ticker symbol (e.g. micron, apple, bca, TSLA)"),
    limit: int = Query(6, ge=1, le=20, description="Max search results to return")
):
    """Search stocks by company name, alias, or ticker symbol."""
    try:
        results = search_stocks(q, limit)
        return {"count": len(results), "data": results}
    except Exception as e:
        logger.error("Stock search endpoint error: %s", str(e))
        raise HTTPException(status_code=500, detail=f"Stock search failed: {str(e)}")


@app.get("/api/v1/stocks/{ticker}")
def get_stock(ticker: str):
    """Get real-time / latest quote for a stock ticker."""
    try:
        return get_single_quote(ticker)
    except ValueError as ve:
        raise HTTPException(status_code=404, detail=str(ve))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Internal server error: {str(e)}")


@app.get("/api/v1/stocks/{ticker}/fundamentals")
def get_fundamentals(ticker: str):
    """Get financial valuation fundamentals (P/E, PBV, ROE, Market Cap, etc.)."""
    try:
        return get_stock_fundamentals(ticker)
    except ValueError as ve:
        raise HTTPException(status_code=404, detail=str(ve))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Internal server error: {str(e)}")


@app.get("/api/v1/stocks/{ticker}/market-data")
async def get_market_data_endpoint(
    ticker: str,
    refresh: bool = Query(False, description="Force refresh market data from Yahoo Finance")
):
    """
    Get consolidated market snapshot containing 7-period performance changes (24h, 1w, 1m, 3m, ytd, 1y, 5y)
    and fundamental valuation metrics (Forward P/E, EPS, Forward EPS, PBV, FCF) cached in PostgreSQL.
    """
    try:
        data = await get_or_sync_market_data(ticker, force_refresh=refresh)
        if not data:
            raise HTTPException(status_code=404, detail=f"Market data not found for '{ticker}'")
        return data
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to fetch market data: {str(e)}")


@app.get("/api/v1/stocks/{ticker}/history")
def get_history(
    ticker: str,
    period: str = Query("1mo", description="Timeframe: 24h, 1w, 1m, 3m, ytd, 1y, 5y")
):
    """Get historical price series for interactive line chart."""
    try:
        return get_stock_history(ticker, period)
    except ValueError as ve:
        raise HTTPException(status_code=404, detail=str(ve))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to fetch stock history: {str(e)}")


@app.get("/api/v1/market/summary")
def get_summary():
    """Get IHSG index performance and benchmark IDX stock prices."""
    try:
        return get_market_summary()
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to fetch market summary: {str(e)}")


@app.get("/api/v1/stocks/{ticker}/sec")
def get_sec(
    ticker: str,
    limit: int = Query(10, ge=1, le=50, description="Max SEC filings to retrieve")
):
    """
    Retrieve SEC Filings (Form 10-K, 10-Q, 8-K) from Yahoo Finance / EDGAR.
    Available for US stocks (e.g. MU, NVDA, AAPL, TSLA).
    """
    try:
        return get_sec_filings(ticker, limit)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to fetch SEC filings: {str(e)}")


# ==============================================================================
# RAG (Retrieval-Augmented Generation) & Knowledge Base Endpoints (Zilliz Cloud)
# ==============================================================================

@app.post("/api/v1/rag/sync")
async def sync_rag_knowledge(
    user_id: str = Query("default_user", description="User ID"),
    sync_sec: bool = Query(True, description="Also sync SEC filings for US holdings")
):
    """
    Synchronize PostgreSQL portfolio holdings, SEC filings, and RSS news into Zilliz Cloud Milvus.
    """
    stats = {"portfolio_synced": 0, "sec_synced": 0, "news_synced": 0}
    try:
        # 1. Sync User Portfolio Holdings
        holdings = await get_user_holdings(user_id)
        if holdings:
            stats["portfolio_synced"] = sync_portfolio_to_milvus(user_id, holdings)

            # 2. Sync SEC Filings for each holding
            if sync_sec:
                for h in holdings:
                    ticker = str(h.get("ticker", "")).strip().upper()
                    if ticker and not ticker.endswith(".JK"):
                        try:
                            sec_data = get_sec_filings(ticker, limit=5)
                            filings = sec_data.get("filings", [])
                            if filings:
                                stats["sec_synced"] += sync_sec_to_milvus(ticker, filings)
                        except Exception as e:
                            logger.warning("Failed to sync SEC for %s: %s", ticker, str(e))

        # 3. Sync Recent News Articles
        recent_news = await get_recent_news(limit=25)
        if recent_news:
            stats["news_synced"] = sync_news_to_milvus(recent_news)

        return {
            "status": "success",
            "message": "Zilliz Cloud knowledge base synchronized successfully.",
            "stats": stats
        }
    except Exception as e:
        logger.error("RAG knowledge sync failed: %s", str(e))
        raise HTTPException(status_code=500, detail=f"Failed to sync knowledge base: {str(e)}")


@app.post("/api/v1/rag/query")
def query_rag_knowledge(req: RAGQueryRequest):
    """
    Semantic hybrid search against Zilliz Cloud knowledge base (SEC, Portfolio, News).
    Returns grounded context and structured citations with distinct badge labels.
    """
    try:
        hits = search_knowledge_hybrid(
            query_text=req.query,
            ticker=req.ticker,
            user_id=req.user_id,
            limit=req.limit or 5
        )

        snippets = []
        for h in hits:
            snippets.append(f"[{h['badge_label']}] {h['title']}: {h['content']}")

        grounding_context = "\n".join(snippets)

        return {
            "query": req.query,
            "grounding_context": grounding_context,
            "count": len(hits),
            "citations": hits
        }
    except Exception as e:
        logger.error("RAG query failed: %s", str(e))
        raise HTTPException(status_code=500, detail=f"Failed to execute RAG query: {str(e)}")


@app.get("/api/v1/rag/search")
def search_rag_knowledge(
    q: str = Query(..., description="Semantic search query"),
    ticker: Optional[str] = Query(None, description="Optional ticker filter"),
    user_id: Optional[str] = Query("default_user", description="User ID"),
    limit: int = Query(5, ge=1, le=20, description="Max results")
):
    """
    Direct inspection endpoint for semantic search over Zilliz Cloud Milvus.
    """
    try:
        hits = search_knowledge_hybrid(
            query_text=q,
            ticker=ticker,
            user_id=user_id,
            limit=limit
        )
        return {
            "query": q,
            "count": len(hits),
            "results": hits
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ==============================================================================
# Cloud Agent Tools Endpoints (MCP & Remote Execution Ready)
# ==============================================================================

@app.get("/api/v1/agent/movers")
def api_agent_movers(type: str = Query("gainers", description="Type of movers: 'gainers' or 'losers'")):
    """Tool: Get Market Movers (Gainers / Losers)"""
    try:
        return get_market_movers(type)
    except Exception as e:
        logger.error("Agent movers tool failed: %s", str(e))
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/v1/agent/fundamentals/{ticker}")
def api_agent_fundamentals(ticker: str):
    """Tool: Get Stock Valuation and Fundamentals (P/E, PBV, ROE, Market Cap)"""
    try:
        return get_stock_fundamentals_tool(ticker)
    except Exception as e:
        logger.error("Agent fundamentals tool failed for %s: %s", ticker, str(e))
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/v1/agent/compare")
def api_agent_compare(req: CompareStocksRequest):
    """Tool: Compare two or more stocks side-by-side"""
    try:
        return compare_stocks(req.tickers)
    except Exception as e:
        logger.error("Agent compare tool failed: %s", str(e))
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/v1/agent/news")
async def api_agent_news(count: int = Query(5, ge=1, le=20, description="Number of news articles")):
    """Tool: Get latest financial news articles"""
    try:
        return await get_agent_latest_news(count)
    except Exception as e:
        logger.error("Agent latest news failed: %s", str(e))
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/v1/agent/news/search")
def api_agent_search_news(q: str = Query(..., description="Query term"), limit: int = Query(5, ge=1, le=20)):
    """Tool: Semantic RAG search for news articles"""
    try:
        return search_agent_market_news(q, limit)
    except Exception as e:
        logger.error("Agent search news failed: %s", str(e))
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/v1/agent/portfolio-news")
async def api_agent_portfolio_news(
    ticker: Optional[str] = Query(None, description="Optional single ticker or 'ALL'"),
    x_user_id: Optional[str] = Header("default_user", alias="X-User-Id")
):
    """Tool: Get News for User's Portfolio Holdings"""
    try:
        return await get_agent_portfolio_news(user_id=x_user_id, ticker=ticker)
    except Exception as e:
        logger.error("Agent portfolio news failed: %s", str(e))
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/v1/agent/news-impact")
async def api_agent_news_impact(req: NewsImpactRequest):
    """Tool: Analyze Sentiment and Price Impact of News or Topic"""
    try:
        return await analyze_news_impact(req.topic)
    except Exception as e:
        logger.error("Agent news impact failed: %s", str(e))
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/v1/agent/portfolio-impact")
async def api_agent_portfolio_impact(
    req: PortfolioImpactRequest,
    x_user_id: Optional[str] = Header("default_user", alias="X-User-Id")
):
    """Tool: Analyze Portfolio Exposure to Macroeconomic Events"""
    try:
        uid = req.user_id or x_user_id or "default_user"
        return await analyze_portfolio_impact(user_id=uid, event=req.event)
    except Exception as e:
        logger.error("Agent portfolio impact failed: %s", str(e))
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/v1/agent/consult")
async def api_agent_consult(
    req: ConsultCloudAgentRequest,
    x_user_id: Optional[str] = Header("default_user", alias="X-User-Id")
):
    """
    Endpoint for Apple FoundationModels on iOS to consult the Gemini Cloud Research Analyst.
    Executes deep vector RAG, SEC filings, live Yahoo Finance fundamentals, and Gemini 3.6 Flash synthesis.
    """
    uid = req.user_id or x_user_id or "default_user"
    try:
        return await consult_cloud_analyst(query=req.query, ticker=req.ticker, user_id=uid)
    except Exception as e:
        logger.error("Cloud Agent consultation failed: %s", str(e))
        raise HTTPException(status_code=500, detail=str(e))


# ==============================================================================
# Model Context Protocol (MCP) Server Integration
# ==============================================================================

try:
    from mcp_server import get_sse_app, mcp_server
    app.mount("/mcp", get_sse_app())
    logger.info("✅ Mounted Model Context Protocol (MCP) Server at /mcp (SSE endpoint: /mcp/sse)")
except Exception as e:
    logger.warning("⚠️ Failed to mount MCP Server: %s", str(e))


@app.get("/api/v1/mcp/tools")
async def list_mcp_tools():
    """
    Returns the metadata and JSON input schema for all available MCP tools
    registered on the FinGent MCP Server.
    """
    try:
        from mcp_server import mcp_server
        tools = await mcp_server.list_tools()
        formatted = []
        for t in tools:
            formatted.append({
                "name": t.name,
                "description": t.description,
                "input_schema": t.input_schema
            })
        return {
            "server": "FinGent Financial Intelligence Server",
            "protocol": "Model Context Protocol (MCP)",
            "count": len(formatted),
            "sse_endpoint": "/mcp/sse",
            "tools": formatted
        }
    except Exception as e:
        logger.error("Failed to list MCP tools: %s", str(e))
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
