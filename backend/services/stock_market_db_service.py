import asyncio
import datetime
import logging
from typing import Any, Dict, List, Optional
import yfinance as yf

from database import fetch_all, fetch_one, is_connected
from services.yahoo_service import get_stock_fundamentals, strip_jk, normalize_ticker

logger = logging.getLogger("FinGent.StockMarketDB")


def _calculate_period_returns(hist, current_price: float) -> Dict[str, Optional[float]]:
    """
    Calculates 7 periodic percentage returns from 5-year historical price data:
    24h, 1W, 1M, 3M, YTD, 1Y, 5Y.
    """
    if hist is None or hist.empty:
        return {
            "change_24h": None,
            "change_1w": None,
            "change_1m": None,
            "change_3m": None,
            "change_ytd": None,
            "change_1y": None,
            "change_5y": None,
        }

    now = datetime.datetime.now(hist.index.tz) if hist.index.tz else datetime.datetime.now()

    # 24H: Compare against previous session close
    if len(hist) >= 2:
        p24 = float(hist["Close"].iloc[-2])
        c24h = round(((current_price - p24) / p24) * 100, 2) if p24 > 0 else 0.0
    else:
        c24h = 0.0

    def _get_return_days_ago(days: int) -> float:
        target = now - datetime.timedelta(days=days)
        sub = hist[hist.index <= target]
        base = float(sub["Close"].iloc[-1]) if not sub.empty else float(hist["Close"].iloc[0])
        return round(((current_price - base) / base) * 100, 2) if base > 0 else 0.0

    c1w = _get_return_days_ago(7)
    c1m = _get_return_days_ago(30)
    c3m = _get_return_days_ago(90)

    # YTD: Compare against first trading session close of current year
    ytd_sub = hist[hist.index.year == now.year]
    ytd_base = float(ytd_sub["Close"].iloc[0]) if not ytd_sub.empty else float(hist["Close"].iloc[0])
    cytd = round(((current_price - ytd_base) / ytd_base) * 100, 2) if ytd_base > 0 else 0.0

    c1y = _get_return_days_ago(365)
    
    # 5Y: Compare against earliest close in 5y historical data
    c5_base = float(hist["Close"].iloc[0])
    c5y = round(((current_price - c5_base) / c5_base) * 100, 2) if c5_base > 0 else 0.0

    return {
        "change_24h": c24h,
        "change_1w": c1w,
        "change_1m": c1m,
        "change_3m": c3m,
        "change_ytd": cytd,
        "change_1y": c1y,
        "change_5y": c5y,
    }


async def get_cached_market_data(ticker: str, max_age_hours: int = 1) -> Optional[Dict[str, Any]]:
    """
    Retrieves market data snapshot from stock_market_data if fresh (< max_age_hours).
    """
    if not is_connected():
        return None

    clean_ticker = strip_jk(ticker)
    query = f"""
    SELECT 
        ticker, name, sector, currency, current_price,
        change_24h, change_1w, change_1m, change_3m, change_ytd, change_1y, change_5y,
        forward_pe, eps, forward_eps, pbv_ratio, free_cashflow,
        trailing_pe, roe, market_cap, dividend_yield, updated_at,
        (updated_at > NOW() - INTERVAL '{max_age_hours} hour') AS is_fresh
    FROM stock_market_data
    WHERE ticker = $1;
    """
    record = await fetch_one(query, clean_ticker)
    if record and record.get("is_fresh"):
        return record
    return None


async def sync_ticker_market_data(ticker: str) -> Dict[str, Any]:
    """
    Fetches latest price, 5-year history, and fundamental valuation metrics via yfinance,
    calculates 7-period performance changes, and upserts into stock_market_data table.
    """
    if not is_connected():
        raise RuntimeError("PostgreSQL database is disconnected.")

    clean_ticker = strip_jk(ticker)

    # 1. Fetch Fundamentals (handles caching and resolving Yahoo ticker symbol)
    fund = await asyncio.to_thread(get_stock_fundamentals, clean_ticker)
    yahoo_sym = fund.get("yahoo_ticker") or normalize_ticker(ticker)

    # 2. Fetch 5-Year History in background thread
    def _fetch_hist():
        stock = yf.Ticker(yahoo_sym)
        return stock.history(period="5y")

    hist = await asyncio.to_thread(_fetch_hist)

    # 3. Determine current price
    if not hist.empty:
        current_price = round(float(hist["Close"].iloc[-1]), 2)
    else:
        # Fallback to single quote or 0.0
        stock = yf.Ticker(yahoo_sym)
        current_price = round(float(stock.fast_info.last_price or 0.0), 2)

    # 4. Compute 7 Period Returns
    returns = _calculate_period_returns(hist, current_price)

    # 5. Extract Fundamentals & Multiples
    forward_pe = fund.get("forward_pe")
    eps = fund.get("eps")
    forward_eps = fund.get("forward_eps")
    pbv_ratio = fund.get("pbv_ratio")
    free_cashflow = fund.get("free_cashflow")
    trailing_pe = fund.get("pe_ratio")
    roe = fund.get("roe")
    market_cap = float(fund.get("market_cap") or 0.0)
    dividend_yield = fund.get("dividend_yield")
    name = fund.get("name") or clean_ticker
    sector = fund.get("sector") or "Diversified"
    currency = fund.get("currency") or ("USD" if yahoo_sym == clean_ticker else "IDR")

    # 6. Upsert into stock_market_data
    upsert_query = """
    INSERT INTO stock_market_data (
        ticker, name, sector, currency, current_price,
        change_24h, change_1w, change_1m, change_3m, change_ytd, change_1y, change_5y,
        forward_pe, eps, forward_eps, pbv_ratio, free_cashflow,
        trailing_pe, roe, market_cap, dividend_yield, updated_at
    ) VALUES (
        $1, $2, $3, $4, $5,
        $6, $7, $8, $9, $10, $11, $12,
        $13, $14, $15, $16, $17,
        $18, $19, $20, $21, CURRENT_TIMESTAMP
    )
    ON CONFLICT (ticker) DO UPDATE SET
        name = EXCLUDED.name,
        sector = EXCLUDED.sector,
        currency = EXCLUDED.currency,
        current_price = EXCLUDED.current_price,
        change_24h = EXCLUDED.change_24h,
        change_1w = EXCLUDED.change_1w,
        change_1m = EXCLUDED.change_1m,
        change_3m = EXCLUDED.change_3m,
        change_ytd = EXCLUDED.change_ytd,
        change_1y = EXCLUDED.change_1y,
        change_5y = EXCLUDED.change_5y,
        forward_pe = EXCLUDED.forward_pe,
        eps = EXCLUDED.eps,
        forward_eps = EXCLUDED.forward_eps,
        pbv_ratio = EXCLUDED.pbv_ratio,
        free_cashflow = EXCLUDED.free_cashflow,
        trailing_pe = EXCLUDED.trailing_pe,
        roe = EXCLUDED.roe,
        market_cap = EXCLUDED.market_cap,
        dividend_yield = EXCLUDED.dividend_yield,
        updated_at = CURRENT_TIMESTAMP
    RETURNING *;
    """

    record = await fetch_one(
        upsert_query,
        clean_ticker,
        name,
        sector,
        currency,
        current_price,
        returns["change_24h"],
        returns["change_1w"],
        returns["change_1m"],
        returns["change_3m"],
        returns["change_ytd"],
        returns["change_1y"],
        returns["change_5y"],
        forward_pe,
        eps,
        forward_eps,
        pbv_ratio,
        free_cashflow,
        trailing_pe,
        roe,
        market_cap,
        dividend_yield,
    )
    logger.info("✅ Synced market data for %s: Price=%s, 24h=%s%%, FWD_PE=%s", clean_ticker, current_price, returns["change_24h"], forward_pe)
    return record or {}


async def get_or_sync_market_data(ticker: str, force_refresh: bool = False) -> Dict[str, Any]:
    """
    Returns fresh market data from DB cache, or triggers sync if stale or missing.
    """
    clean_ticker = strip_jk(ticker)
    if not force_refresh:
        cached = await get_cached_market_data(clean_ticker)
        if cached:
            return cached

    try:
        return await sync_ticker_market_data(clean_ticker)
    except Exception as e:
        logger.warning("Failed to sync market data for %s: %s. Checking for stale record.", clean_ticker, e)
        # Fallback to any existing record in DB even if older than 1 hour
        stale = await fetch_one("SELECT * FROM stock_market_data WHERE ticker = $1;", clean_ticker)
        if stale:
            return stale
        return {}


async def ensure_tickers_market_data(tickers: List[str]) -> None:
    """
    Checks a list of tickers and syncs any missing or stale records in parallel.
    """
    if not is_connected() or not tickers:
        return

    clean_tickers = list({strip_jk(t) for t in tickers if t})
    if not clean_tickers:
        return

    # Check which tickers are fresh in DB
    query = """
    SELECT ticker
    FROM stock_market_data
    WHERE ticker = ANY($1::varchar[])
      AND updated_at > NOW() - INTERVAL '1 hour';
    """
    fresh_rows = await fetch_all(query, clean_tickers)
    fresh_set = {r["ticker"] for r in fresh_rows}

    stale_or_missing = [t for t in clean_tickers if t not in fresh_set]
    if not stale_or_missing:
        return

    logger.info("Syncing market data for tickers: %s", stale_or_missing)

    async def _safe_sync(t: str):
        try:
            await sync_ticker_market_data(t)
        except Exception as err:
            logger.warning("Could not sync market data for %s: %s", t, err)

    await asyncio.gather(*[_safe_sync(t) for t in stale_or_missing], return_exceptions=True)
