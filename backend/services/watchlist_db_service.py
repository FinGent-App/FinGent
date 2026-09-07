import logging
from typing import List, Dict, Any, Optional
from database import fetch_all, fetch_one, execute, is_connected

logger = logging.getLogger("FinGent.WatchlistDB")


async def get_user_watchlist(user_id: str = "default_user") -> List[Dict[str, Any]]:
    """
    Returns the user's favorite / watchlist stock tickers ordered by most recently added.
    """
    if not is_connected():
        return []

    query = """
    SELECT id, user_id, ticker, notes, added_at
    FROM user_watchlists
    WHERE user_id = $1
    ORDER BY added_at DESC;
    """
    return await fetch_all(query, user_id)


async def add_to_watchlist(
    ticker: str,
    user_id: str = "default_user",
    notes: Optional[str] = None
) -> Dict[str, Any]:
    """
    Adds a stock ticker to user favorites. If already exists, returns existing record.
    """
    if not is_connected():
        raise RuntimeError("PostgreSQL database is disconnected.")

    clean_ticker = ticker.strip().upper()

    query = """
    INSERT INTO user_watchlists (user_id, ticker, notes)
    VALUES ($1, $2, $3)
    ON CONFLICT (user_id, ticker) DO UPDATE
        SET notes = COALESCE(EXCLUDED.notes, user_watchlists.notes)
    RETURNING id, user_id, ticker, notes, added_at;
    """
    record = await fetch_one(query, user_id, clean_ticker, notes)
    return record or {"user_id": user_id, "ticker": clean_ticker}


async def remove_from_watchlist(ticker: str, user_id: str = "default_user") -> bool:
    """
    Removes a stock ticker from user favorites. Returns True if deleted.
    """
    if not is_connected():
        raise RuntimeError("PostgreSQL database is disconnected.")

    clean_ticker = ticker.strip().upper()
    query = """
    DELETE FROM user_watchlists
    WHERE user_id = $1 AND ticker = $2;
    """
    res = await execute(query, user_id, clean_ticker)
    return "DELETE 1" in res


async def is_in_watchlist(ticker: str, user_id: str = "default_user") -> bool:
    """
    Checks if a given stock ticker is favorited by the user.
    """
    if not is_connected():
        return False

    clean_ticker = ticker.strip().upper()
    query = """
    SELECT 1 FROM user_watchlists
    WHERE user_id = $1 AND ticker = $2
    LIMIT 1;
    """
    record = await fetch_one(query, user_id, clean_ticker)
    return record is not None
