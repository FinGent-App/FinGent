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
    get_stock_history
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
            "/api/v1/stocks/batch?tickers=BBCA,TLKM,BBRI",
            "/api/v1/stocks/{ticker}/fundamentals",
            "/api/v1/market/summary"
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


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
