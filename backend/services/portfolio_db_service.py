import asyncio
import logging
from typing import List, Dict, Any, Optional
from database import fetch_all, fetch_one, execute, is_connected

from services.stock_market_db_service import ensure_tickers_market_data

logger = logging.getLogger("FinGent.PortfolioDB")


async def get_user_holdings(user_id: str = "default_user") -> List[Dict[str, Any]]:
    """
    Retrieves all portfolio holdings for a user matching the Swift UserHolding model,
    enriched with real-time market price, 7-period historical performance changes,
    and fundamental valuation metrics via LEFT JOIN stock_market_data.
    """
    if not is_connected():
        return []

    # 1. Fetch user's tickers to ensure market data cache is warm
    try:
        user_tickers = await fetch_all("SELECT DISTINCT ticker FROM portfolio_holdings WHERE user_id = $1;", user_id)
        ticker_list = [r["ticker"] for r in user_tickers if r.get("ticker")]
        if ticker_list:
            await ensure_tickers_market_data(ticker_list)
    except Exception as e:
        logger.warning("Error ensuring market data for user holdings: %s", e)

    # 2. Query enriched holdings joined with market and fundamental data
    query = """
    SELECT 
        h.id, h.user_id, h.ticker, h.name, h.shares, h.price_per_share, h.invested_amount, h.sector, h.updated_at,
        m.current_price,
        m.currency,
        m.change_24h,
        m.change_1w,
        m.change_1m,
        m.change_3m,
        m.change_ytd,
        m.change_1y,
        m.change_5y,
        m.forward_pe,
        m.eps,
        m.forward_eps,
        m.pbv_ratio,
        m.free_cashflow,
        m.trailing_pe,
        m.roe,
        m.market_cap,
        m.dividend_yield,
        m.updated_at AS market_updated_at
    FROM portfolio_holdings h
    LEFT JOIN stock_market_data m ON h.ticker = m.ticker
    WHERE h.user_id = $1
    ORDER BY h.updated_at DESC;
    """
    return await fetch_all(query, user_id)


async def upsert_holding(
    ticker: str,
    name: str,
    shares: int,
    price_per_share: float,
    invested_amount: float,
    sector: str = "Technology",
    user_id: str = "default_user"
) -> Dict[str, Any]:
    """
    Inserts or updates a stock holding in user portfolio.
    """
    if not is_connected():
        raise RuntimeError("PostgreSQL database is disconnected.")

    clean_ticker = ticker.strip().upper()

    query = """
    INSERT INTO portfolio_holdings (
        user_id, ticker, name, shares, price_per_share, invested_amount, sector, updated_at
    ) VALUES (
        $1, $2, $3, $4, $5, $6, $7, CURRENT_TIMESTAMP
    )
    ON CONFLICT (user_id, ticker) DO UPDATE SET
        name = EXCLUDED.name,
        shares = EXCLUDED.shares,
        price_per_share = EXCLUDED.price_per_share,
        invested_amount = EXCLUDED.invested_amount,
        sector = EXCLUDED.sector,
        updated_at = CURRENT_TIMESTAMP
    RETURNING id, user_id, ticker, name, shares, price_per_share, invested_amount, sector, updated_at;
    """
    record = await fetch_one(
        query, user_id, clean_ticker, name, shares, price_per_share, invested_amount, sector
    )
    # Warm market data in background
    asyncio.create_task(ensure_tickers_market_data([clean_ticker]))
    return record or {}


async def delete_holding(ticker: str, user_id: str = "default_user") -> bool:
    """
    Removes a holding when a user completely closes a position.
    """
    if not is_connected():
        raise RuntimeError("PostgreSQL database is disconnected.")

    clean_ticker = ticker.strip().upper()
    query = """
    DELETE FROM portfolio_holdings
    WHERE user_id = $1 AND ticker = $2;
    """
    res = await execute(query, user_id, clean_ticker)
    return "DELETE 1" in res


async def record_transaction(
    ticker: str,
    tx_type: str,
    shares: int,
    price_per_share: float,
    user_id: str = "default_user"
) -> Dict[str, Any]:
    """
    Records a buy or sell transaction in trade history.
    """
    if not is_connected():
        raise RuntimeError("PostgreSQL database is disconnected.")

    clean_ticker = ticker.strip().upper()
    total_amount = float(shares) * float(price_per_share)

    query = """
    INSERT INTO portfolio_transactions (
        user_id, ticker, type, shares, price_per_share, total_amount
    ) VALUES (
        $1, $2, $3, $4, $5, $6
    )
    RETURNING id, user_id, ticker, type, shares, price_per_share, total_amount, executed_at;
    """
    record = await fetch_one(
        query, user_id, clean_ticker, tx_type.upper(), shares, price_per_share, total_amount
    )
    return record or {}


async def get_user_transactions(
    user_id: str = "default_user",
    limit: int = 50
) -> List[Dict[str, Any]]:
    """
    Retrieves chronological trade execution history for user.
    """
    if not is_connected():
        return []

    query = """
    SELECT id, user_id, ticker, type, shares, price_per_share, total_amount, executed_at
    FROM portfolio_transactions
    WHERE user_id = $1
    ORDER BY executed_at DESC
    LIMIT $2;
    """
    return await fetch_all(query, user_id, limit)
