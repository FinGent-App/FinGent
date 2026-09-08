import re
import html
import hashlib
import logging
from datetime import datetime, timezone
import xml.etree.ElementTree as ET
import email.utils
from typing import List, Dict, Any, Optional, Set
import httpx
from database import fetch_all, is_connected
from services.news_db_service import upsert_news_articles

logger = logging.getLogger("FinGent.RSS")

# Curated global/US stock alias dictionary (Company Name / Keyword -> Ticker)
# Focused on major US equities, semiconductor leaders, and global tech leaders
GLOBAL_COMPANY_ALIASES: Dict[str, List[str]] = {
    "MU": ["micron", "micron technology"],
    "NVDA": ["nvidia", "nvidia corp"],
    "AMD": ["advanced micro devices", "amd"],
    "AAPL": ["apple", "apple inc"],
    "MSFT": ["microsoft"],
    "TSLA": ["tesla", "tesla motors"],
    "GOOGL": ["alphabet", "google"],
    "GOOG": ["google"],
    "META": ["meta platforms", "facebook"],
    "AMZN": ["amazon", "amazon.com"],
    "INTC": ["intel", "intel corp"],
    "QCOM": ["qualcomm"],
    "AVGO": ["broadcom"],
    "TSM": ["tsmc", "taiwan semiconductor"],
    "ARM": ["arm holdings", "arm"],
    "SMCI": ["super micro", "supermicro"],
    "PLTR": ["palantir"],
    "NFLX": ["netflix"],
    "COIN": ["coinbase"],
    "ORCL": ["oracle"],
    "CRM": ["salesforce"],
    "UBER": ["uber"],
    "BABA": ["alibaba"],
}

# Alias for backwards compatibility
KNOWN_TICKERS = GLOBAL_COMPANY_ALIASES

# Common English words and financial acronyms to prevent false positive ticker matches
COMMON_WORD_BLACKLIST: Set[str] = {
    "A", "I", "IN", "ON", "AN", "AT", "BY", "FOR", "IF", "IS", "IT", "OF",
    "OR", "TO", "UP", "US", "BE", "DO", "GO", "HE", "ME", "MY", "NO", "SO",
    "WE", "ALL", "ARE", "AND", "CAN", "OUT", "NEW", "NOW", "ONE", "SEE",
    "BUY", "PAY", "KEY", "TOP", "BIG", "CEO", "CFO", "CTO", "GDP", "CPI",
    "FED", "SEC", "IPO", "ETF", "AI", "EV", "USA", "USD", "IDR", "EUR",
    "GBP", "JPY", "EST", "PST", "GMT", "UTC", "AM", "PM", "THE", "NOT"
}

# Regex patterns for explicit financial symbols (Cashtags, Exchange Parentheses, Standalone Parentheses)
EXPLICIT_TICKER_PATTERNS = [
    re.compile(r"\$([A-Z]{1,5})\b"),                                   # $MU, $AAPL
    re.compile(r"\((?:NASDAQ|NYSE|AMEX|IDX):\s*([A-Z]{1,5})\)", re.I), # (NASDAQ: AAPL)
    re.compile(r"\(([A-Z]{1,5})\)"),                                   # (MU), (BBCA)
]

# RSS Feed endpoints
YAHOO_TOP_NEWS_URL = "https://finance.yahoo.com/news/rssindex"
CNBC_TOP_NEWS_URL = "https://search.cnbc.com/rs/search/combinedcms/view.xml?partnerId=wrss01&id=10000664"
YAHOO_TICKER_FEED_URL = "https://feeds.finance.yahoo.com/rss/2.0/headline?s={ticker}"


async def get_tracked_tickers_from_db() -> Set[str]:
    """
    Fetches unique tickers dynamically from user watchlists, portfolio holdings,
    and stock market data tables in PostgreSQL.
    """
    if not is_connected():
        return set()

    try:
        rows = await fetch_all("""
            SELECT DISTINCT ticker FROM (
                SELECT ticker FROM portfolio_holdings
                UNION
                SELECT ticker FROM user_watchlists
                UNION
                SELECT ticker FROM stock_market_data
            ) t WHERE ticker IS NOT NULL AND ticker != ''
        """)
        return {r["ticker"].strip().upper() for r in rows if r.get("ticker")}
    except Exception as e:
        logger.warning("Failed to fetch tracked tickers from DB: %s", str(e))
        return set()


def _generate_deterministic_id(url: str) -> str:
    """Generates a unique SHA-256 hash from canonical URL."""
    return hashlib.sha256(url.strip().encode("utf-8")).hexdigest()


def _clean_text(raw_text: Optional[str]) -> str:
    """Sanitizes text by stripping HTML tags and decoding HTML entities."""
    if not raw_text:
        return ""
    clean = re.sub(r"<[^>]+>", " ", raw_text)
    clean = html.unescape(clean)
    clean = re.sub(r"\s+", " ", clean).strip()
    return clean


def _parse_date(date_str: Optional[str]) -> datetime:
    """Parses RFC-822 or ISO-8601 dates safely."""
    if not date_str:
        return datetime.now(timezone.utc)
    try:
        dt = email.utils.parsedate_to_datetime(date_str)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt
    except Exception:
        try:
            return datetime.fromisoformat(date_str)
        except Exception:
            return datetime.now(timezone.utc)


def extract_tickers(
    title: str,
    summary: str,
    dynamic_tickers: Optional[Set[str]] = None
) -> List[str]:
    """
    Extracts stock tickers based on:
    1. Explicit financial syntaxes ($TICKER, (NASDAQ: TICKER), (TICKER))
    2. Dynamically tracked tickers from the database (user holdings/watchlists)
    3. Curated global company name aliases (e.g. 'NVIDIA' -> 'NVDA')
    Filters out common word false positives using COMMON_WORD_BLACKLIST.
    """
    combined = f"{title} {summary}"
    combined_upper = combined.upper()
    combined_lower = combined.lower()
    found: Set[str] = set()

    # 1. Explicit Financial Symbol Patterns ($TICKER, (NASDAQ: TICKER), (TICKER))
    for pattern in EXPLICIT_TICKER_PATTERNS:
        for match in pattern.finditer(combined):
            symbol = match.group(1).upper()
            if symbol not in COMMON_WORD_BLACKLIST:
                found.add(symbol)

    # 2. Dynamic Tickers from Database (Watchlist, Portfolio, Market Data)
    if dynamic_tickers:
        for ticker in dynamic_tickers:
            clean_ticker = ticker.strip().upper()
            if clean_ticker and clean_ticker not in COMMON_WORD_BLACKLIST:
                if re.search(rf"\b{re.escape(clean_ticker)}\b", combined_upper):
                    found.add(clean_ticker)

    # 3. Curated Global Company Name Aliases
    for ticker, keywords in GLOBAL_COMPANY_ALIASES.items():
        if ticker in found:
            continue
        # Direct ticker match as whole word
        if re.search(rf"\b{re.escape(ticker)}\b", combined_upper) and ticker not in COMMON_WORD_BLACKLIST:
            found.add(ticker)
            continue
        # Company name alias match
        for kw in keywords:
            if re.search(rf"\b{re.escape(kw)}\b", combined_lower):
                found.add(ticker)
                break

    return sorted(list(found))


def _parse_xml_feed(
    xml_content: str,
    source_name: str,
    dynamic_tickers: Optional[Set[str]] = None
) -> List[Dict[str, Any]]:
    """Parses RSS/Atom XML content into structured article dicts."""
    articles = []
    try:
        root = ET.fromstring(xml_content)
    except Exception as e:
        logger.warning("Failed to parse RSS XML from %s: %s", source_name, str(e))
        return []

    # Check for RSS channel -> items
    items = root.findall(".//item")
    if not items:
        # Check for Atom entries
        items = root.findall(".//{http://www.w3.org/2005/Atom}entry")

    def _find_child(element, candidate_tags):
        for tag in candidate_tags:
            child = element.find(tag)
            if child is not None:
                return child
        return None

    for item in items:
        title_el = _find_child(item, ["title", "{http://www.w3.org/2005/Atom}title"])
        link_el = _find_child(item, ["link", "{http://www.w3.org/2005/Atom}link"])
        desc_el = _find_child(item, ["description", "{http://www.w3.org/2005/Atom}summary", "{http://www.w3.org/2005/Atom}content"])
        pub_el = _find_child(item, ["pubDate", "{http://www.w3.org/2005/Atom}published", "{http://www.w3.org/2005/Atom}updated"])

        title = _clean_text(title_el.text if title_el is not None else "")
        
        # Link handling
        url = ""
        if link_el is not None:
            url = link_el.text or link_el.attrib.get("href", "")
        url = url.strip()

        if not title or not url:
            continue

        summary = _clean_text(desc_el.text if desc_el is not None else "")
        published_at = _parse_date(pub_el.text if pub_el is not None else "")
        article_id = _generate_deterministic_id(url)
        tickers = extract_tickers(title, summary, dynamic_tickers=dynamic_tickers)

        articles.append({
            "id": article_id,
            "title": title,
            "summary": summary,
            "url": url,
            "source": source_name,
            "author": source_name,
            "image_url": None,
            "tickers": tickers,
            "published_at": published_at
        })

    return articles


async def fetch_rss_feed(
    url: str,
    source_name: str,
    dynamic_tickers: Optional[Set[str]] = None
) -> List[Dict[str, Any]]:
    """Fetches and parses a single RSS feed over HTTP."""
    headers = {
        "User-Agent": "FinGent-News-Grounding/1.0 (iOS Investment Assistant; Contact: admin@fingent.app)"
    }
    try:
        async with httpx.AsyncClient(timeout=10.0, follow_redirects=True) as client:
            resp = await client.get(url, headers=headers)
            if resp.status_code == 200:
                return _parse_xml_feed(resp.text, source_name, dynamic_tickers=dynamic_tickers)
            else:
                logger.warning("HTTP %d when fetching %s (%s)", resp.status_code, url, source_name)
                return []
    except Exception as e:
        logger.error("Error fetching feed from %s: %s", url, str(e))
        return []


async def sync_all_rss_feeds() -> int:
    """
    Ingests global news feeds from Yahoo Finance and CNBC and persists them to PostgreSQL.
    Dynamically grounds incoming news against DB-tracked portfolio/watchlist tickers.
    """
    tracked_tickers = await get_tracked_tickers_from_db()
    articles = []
    yahoo_articles = await fetch_rss_feed(YAHOO_TOP_NEWS_URL, "Yahoo Finance", dynamic_tickers=tracked_tickers)
    cnbc_articles = await fetch_rss_feed(CNBC_TOP_NEWS_URL, "CNBC", dynamic_tickers=tracked_tickers)

    articles.extend(yahoo_articles)
    articles.extend(cnbc_articles)

    if not articles:
        return 0

    return await upsert_news_articles(articles)


async def sync_ticker_news(ticker: str) -> int:
    """
    Fetches dedicated news feed for a specific ticker (e.g. MU, NVDA) and saves to DB.
    """
    clean_ticker = ticker.strip().upper().replace(".JK", "")
    feed_url = YAHOO_TICKER_FEED_URL.format(ticker=clean_ticker)
    articles = await fetch_rss_feed(feed_url, f"Yahoo Finance ({clean_ticker})", dynamic_tickers={clean_ticker})

    # Ensure this ticker is tagged in all returned articles
    for art in articles:
        if clean_ticker not in art["tickers"]:
            art["tickers"].append(clean_ticker)

    if not articles:
        return 0

    return await upsert_news_articles(articles)
