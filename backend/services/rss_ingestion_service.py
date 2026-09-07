import re
import html
import hashlib
import logging
from datetime import datetime, timezone
import xml.etree.ElementTree as ET
import email.utils
from typing import List, Dict, Any, Optional
import httpx
from services.news_db_service import upsert_news_articles

logger = logging.getLogger("FinGent.RSS")

# Curated stock dictionary matching Swift StockTickerExtractor
KNOWN_TICKERS = {
    # US Tech & Chips
    "MU": ["micron", "micron technology"],
    "NVDA": ["nvidia", "nvidia corp"],
    "AMD": ["advanced micro devices", "amd"],
    "AAPL": ["apple", "apple inc", "iphone"],
    "MSFT": ["microsoft"],
    "TSLA": ["tesla"],
    "GOOGL": ["alphabet", "google"],
    "GOOG": ["google"],
    "META": ["meta", "meta platforms", "facebook"],
    "AMZN": ["amazon", "amazon.com"],
    "INTC": ["intel", "intel corp"],
    "QCOM": ["qualcomm"],
    "AVGO": ["broadcom"],
    "TSM": ["tsmc", "taiwan semiconductor"],
    "BABA": ["alibaba"],
    # IDX Indonesian Bluechips
    "BBCA": ["bca", "bank central asia"],
    "BBRI": ["bri", "bank rakyat indonesia"],
    "BMRI": ["mandiri", "bank mandiri"],
    "BBNI": ["bni", "bank negara indonesia"],
    "TLKM": ["telkom", "telkom indonesia"],
    "ASII": ["astra", "astra international"],
    "GOTO": ["goto", "gojek tokopedia"],
    "UNVR": ["unilever indonesia", "unilever"],
    "ICBP": ["indofood cbp"],
    "INDF": ["indofood"],
    "ADRO": ["adaro", "adaro energy"],
    "PTBA": ["bukit asam"],
}

# RSS Feed endpoints
YAHOO_TOP_NEWS_URL = "https://finance.yahoo.com/news/rssindex"
CNBC_TOP_NEWS_URL = "https://search.cnbc.com/rs/search/combinedcms/view.xml?partnerId=wrss01&id=10000664"
YAHOO_TICKER_FEED_URL = "https://feeds.finance.yahoo.com/rss/2.0/headline?s={ticker}"


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


def extract_tickers(title: str, summary: str) -> List[str]:
    """
    Extracts stock tickers based on explicit symbols and company name keywords.
    """
    combined = f"{title} {summary}"
    combined_upper = combined.upper()
    combined_lower = combined.lower()
    found = set()

    for ticker, keywords in KNOWN_TICKERS.items():
        # Match explicit ticker with word boundaries: \bMU\b, \bNVDA\b
        if re.search(rf"\b{ticker}\b", combined_upper):
            found.add(ticker)
            continue

        # Match company aliases/keywords
        for kw in keywords:
            if kw in combined_lower:
                found.add(ticker)
                break

    return sorted(list(found))


def _parse_xml_feed(xml_content: str, source_name: str) -> List[Dict[str, Any]]:
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
        tickers = extract_tickers(title, summary)

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


async def fetch_rss_feed(url: str, source_name: str) -> List[Dict[str, Any]]:
    """Fetches and parses a single RSS feed over HTTP."""
    headers = {
        "User-Agent": "FinGent-News-Grounding/1.0 (iOS Investment Assistant; Contact: admin@fingent.app)"
    }
    try:
        async with httpx.AsyncClient(timeout=10.0, follow_redirects=True) as client:
            resp = await client.get(url, headers=headers)
            if resp.status_code == 200:
                return _parse_xml_feed(resp.text, source_name)
            else:
                logger.warning("HTTP %d when fetching %s (%s)", resp.status_code, url, source_name)
                return []
    except Exception as e:
        logger.error("Error fetching feed from %s: %s", url, str(e))
        return []


async def sync_all_rss_feeds() -> int:
    """
    Ingests global news feeds from Yahoo Finance and CNBC and persists them to PostgreSQL.
    """
    articles = []
    yahoo_articles = await fetch_rss_feed(YAHOO_TOP_NEWS_URL, "Yahoo Finance")
    cnbc_articles = await fetch_rss_feed(CNBC_TOP_NEWS_URL, "CNBC")

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
    articles = await fetch_rss_feed(feed_url, f"Yahoo Finance ({clean_ticker})")

    # Ensure this ticker is tagged in all returned articles
    for art in articles:
        if clean_ticker not in art["tickers"]:
            art["tickers"].append(clean_ticker)

    if not articles:
        return 0

    return await upsert_news_articles(articles)
