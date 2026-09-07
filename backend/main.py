import logging
from typing import List
from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from services.yahoo_service import (
    get_single_quote,
    get_batch_quotes,
    get_stock_fundamentals,
    get_market_summary,
    get_stock_history
)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
)

app = FastAPI(
    title="FinGent Backend API",
    description="Realtime Stock Data & Agent Intelligence Service powered by Yahoo Finance",
    version="1.0.0"
)

# Enable CORS for local development and future clients
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/")
def health_check():
    """Health check endpoint to verify backend status."""
    return {
        "status": "online",
        "service": "FinGent Backend API",
        "version": "1.0.0",
        "data_provider": "Yahoo Finance (IDX/BEI .JK)",
        "endpoints": [
            "/api/v1/stocks/{ticker}",
            "/api/v1/stocks/batch?tickers=BBCA,TLKM,BBRI",
            "/api/v1/stocks/{ticker}/fundamentals",
            "/api/v1/market/summary"
        ]
    }


@app.get("/api/v1/stocks/batch")
def get_batch(
    tickers: str = Query(..., description="Comma-separated stock tickers (e.g. BBCA,TLKM,GOTO)")
):
    """
    Get quotes for multiple stocks in a single request.
    Ideal for syncing user portfolio holdings.
    """
    ticker_list = [t.strip() for t in tickers.split(",") if t.strip()]
    if not ticker_list:
        raise HTTPException(status_code=400, detail="Parameter 'tickers' must not be empty.")

    try:
        quotes = get_batch_quotes(ticker_list)
        return {
            "count": len(quotes),
            "data": quotes
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to fetch batch quotes: {str(e)}")


@app.get("/api/v1/stocks/{ticker}")
def get_stock(ticker: str):
    """
    Get real-time / latest quote for a stock ticker.
    Examples: BBCA, TLKM, BBRI, GOTO, ASII
    """
    try:
        return get_single_quote(ticker)
    except ValueError as ve:
        raise HTTPException(status_code=404, detail=str(ve))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Internal server error: {str(e)}")


@app.get("/api/v1/stocks/{ticker}/fundamentals")
def get_fundamentals(ticker: str):
    """
    Get financial valuation fundamentals (P/E, PBV, ROE, Market Cap, Dividend Yield, Sector).
    """
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
    """
    Get historical price series for interactive line chart.
    """
    try:
        return get_stock_history(ticker, period)
    except ValueError as ve:
        raise HTTPException(status_code=404, detail=str(ve))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to fetch stock history: {str(e)}")


@app.get("/api/v1/market/summary")
def get_summary():
    """
    Get IHSG index performance and benchmark IDX stock prices.
    """
    try:
        return get_market_summary()
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to fetch market summary: {str(e)}")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
