import logging
from typing import List, Dict, Any, Optional
from database import fetch_all, fetch_one, fetch_val, execute_many, is_connected

logger = logging.getLogger("FinGent.NewsDB")


async def upsert_news_articles(articles: List[Dict[str, Any]]) -> int:
    """
    Inserts or updates news articles in bulk with deterministic SHA-256 ID deduplication.
    Returns the number of articles processed.
    """
    if not articles or not is_connected():
        return 0

    query = """
    INSERT INTO news_articles (
        id, title, summary, url, source, author, image_url, tickers, published_at
    ) VALUES (
        $1, $2, $3, $4, $5, $6, $7, $8, $9
    )
    ON CONFLICT (id) DO UPDATE SET
        title = EXCLUDED.title,
        summary = EXCLUDED.summary,
        tickers = EXCLUDED.tickers,
        image_url = COALESCE(EXCLUDED.image_url, news_articles.image_url);
    """

    params = []
    for art in articles:
        params.append((
            art["id"],
            art["title"],
            art.get("summary", ""),
            art["url"],
            art.get("source", "Yahoo Finance"),
            art.get("author", "FinGent Agent"),
            art.get("image_url"),
            art.get("tickers", []),
            art["published_at"]
        ))

    try:
        await execute_many(query, params)
        logger.info("Successfully persisted %d articles to news_articles.", len(params))
        return len(params)
    except Exception as e:
        logger.error("Failed to batch upsert news articles: %s", str(e))
        raise e


async def get_news_by_ticker(ticker: str, limit: int = 5) -> List[Dict[str, Any]]:
    """
    Retrieves latest news articles mentioning a given stock ticker.
    Uses GIN index on tickers array for instant retrieval.
    """
    if not is_connected():
        return []

    clean_ticker = ticker.strip().upper().replace(".JK", "")

    query = """
    SELECT 
        id, title, summary, url, source, author, image_url, tickers,
        published_at, fetched_at
    FROM news_articles
    WHERE $1 = ANY(tickers)
    ORDER BY published_at DESC
    LIMIT $2;
    """
    return await fetch_all(query, clean_ticker, limit)


async def get_recent_news(limit: int = 20) -> List[Dict[str, Any]]:
    """
    Retrieves the most recent news articles across all tickers and sources.
    """
    if not is_connected():
        return []

    query = """
    SELECT 
        id, title, summary, url, source, author, image_url, tickers,
        published_at, fetched_at
    FROM news_articles
    ORDER BY published_at DESC
    LIMIT $1;
    """
    return await fetch_all(query, limit)


async def get_news_count() -> int:
    """Returns total number of news articles stored."""
    if not is_connected():
        return 0
    return await fetch_val("SELECT COUNT(*) FROM news_articles;") or 0
