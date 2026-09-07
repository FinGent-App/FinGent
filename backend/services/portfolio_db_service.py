import logging
from typing import List, Dict, Any, Optional
from database import fetch_all, fetch_one, execute, is_connected

logger = logging.getLogger("FinGent.PortfolioDB")


async def get_user_holdings(user_id: str = "default_user") -> List[Dict[str, Any]]:
    """
    Retrieves all portfolio holdings for a user matching the Swift UserHolding model.
    """
    if not is_connected():
        return []

    query = """
    SELECT id, user_id, ticker, name, shares, price_per_share, invested_amount, sector, updated_at
    FROM portfolio_holdings
    WHERE user_id = $1
    ORDER BY updated_at DESC;
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
