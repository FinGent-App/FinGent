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

# ==============================================================================
# Ticker & Market Classification Dictionaries
# ==============================================================================

# Curated global/US stock alias dictionary (Company Name / Keyword -> Ticker)
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

# Curated Indonesian IDX stock alias dictionary
INDONESIAN_COMPANY_ALIASES: Dict[str, List[str]] = {
    "BBCA": ["bca", "bank central asia", "bank bca"],
    "BBRI": ["bri", "bank rakyat indonesia", "bank bri"],
    "BMRI": ["mandiri", "bank mandiri"],
    "BBNI": ["bni", "bank bni", "bank negara indonesia"],
    "TLKM": ["telkom", "telkom indonesia"],
    "ASII": ["astra", "astra international"],
    "GOTO": ["goto", "gojek", "tokopedia"],
    "ICBP": ["indofood cbp", "icbp"],
    "INDF": ["indofood", "indofood sukses makmur"],
    "UNVR": ["unilever", "unilever indonesia"],
    "ANTM": ["antam", "aneka tambang"],
    "AMMN": ["amman", "amman mineral"],
    "BREN": ["barito renewables", "bren"],
    "BRPT": ["barito pacific", "brpt"],
    "KLBF": ["kalbe", "kalbe farma"],
    "PGAS": ["pgas", "perusahaan gas negara", "pertagas"],
    "ADRO": ["adaro", "adaro energy"],
    "PTBA": ["bukit asam", "ptba"],
    "MDKA": ["merdeka copper", "mdka"],
    "ACES": ["ace hardware", "aspirasi hidup indonesia", "aces"],
    "TPIA": ["chandra asri", "tpia"],
    "INKP": ["indah kiat", "inkp"],
    "INCO": ["vale indonesia", "inco"],
    "SMGR": ["semen indonesia", "smgr"],
    "CPIN": ["charoen pokphand", "cpin"],
    "MEDC": ["medco", "medco energi", "medc"],
    "HRUM": ["harum energy", "hrum"],
    "ITMG": ["indo tambangraya", "itmg"],
    "TBIG": ["tower bersama", "tbig"],
    "TOWR": ["sarana menara", "towr"],
    "MYOR": ["mayora", "mayora indah"],
    "JSMR": ["jasa marga", "jsmr"],
    "MIKA": ["mitra keluarga", "mika"],
    "HEAL": ["medikaloka hermosa", "hermina"],
    "GGRM": ["gudang garam", "ggrm"],
    "HMSP": ["sampoerna", "hm sampoerna", "hmsp"],
    "ARTO": ["bank jago", "arto"],
    "BUKA": ["bukalapak", "buka"],
    "EXCL": ["xl axiata", "excl"],
    "ISAT": ["indosat", "isat"],
    "UNTR": ["united tractors", "untr"],
}

POPULAR_IDX_TICKERS: Set[str] = set(INDONESIAN_COMPANY_ALIASES.keys()).union({
    "PWON", "BSDE", "CTRA", "SMRA", "AVIA", "SILO", "MAPI", "MAPA",
    "BFIN", "BTPS", "BBTN", "SRTG", "ERAA", "SSIA", "ELSA", "AKRA"
})

# Alias for backwards compatibility
KNOWN_TICKERS = {**GLOBAL_COMPANY_ALIASES, **INDONESIAN_COMPANY_ALIASES}

# Common English words and financial acronyms to prevent false positive ticker matches
COMMON_WORD_BLACKLIST: Set[str] = {
    "A", "I", "IN", "ON", "AN", "AT", "BY", "FOR", "IF", "IS", "IT", "OF",
    "OR", "TO", "UP", "US", "BE", "DO", "GO", "HE", "ME", "MY", "NO", "SO",
    "WE", "ALL", "ARE", "AND", "CAN", "OUT", "NEW", "NOW", "ONE", "SEE",
    "BUY", "PAY", "KEY", "TOP", "BIG", "CEO", "CFO", "CTO", "GDP", "CPI",
    "FED", "SEC", "IPO", "ETF", "AI", "EV", "USA", "USD", "IDR", "EUR",
    "GBP", "JPY", "EST", "PST", "GMT", "UTC", "AM", "PM", "THE", "NOT",
    "IDX", "IHSG", "LQ45", "BEI", "OJK", "BI", "APBN"
}

# Regex patterns for explicit financial symbols (Cashtags, Exchange Parentheses, Standalone Parentheses)
EXPLICIT_TICKER_PATTERNS = [
    re.compile(r"\$([A-Z]{1,5})\b"),                                   # $MU, $AAPL
    re.compile(r"\((?:NASDAQ|NYSE|AMEX|IDX):\s*([A-Z]{1,5})\)", re.I), # (NASDAQ: AAPL), (IDX: BBCA)
    re.compile(r"\(([A-Z]{1,5})\)"),                                   # (MU), (BBCA)
]

# Source categorization for strict market routing
INDONESIAN_SOURCES: Set[str] = {
    "Kontan", "Detik Finance", "Liputan6 Bisnis", "Tempo Bisnis", "CNN Indonesia Ekonomi"
}

US_GLOBAL_SOURCES: Set[str] = {
    "Yahoo Finance", "CNBC", "Investing.com", "Nasdaq", "GlobeNewswire", "PR Newswire", "Business Wire"
}


def is_idx_ticker(ticker: Optional[str]) -> bool:
    """Returns True if ticker belongs to the Indonesian Stock Exchange (IDX)."""
    if not ticker:
        return False
    t = ticker.strip().upper()
    if t.endswith(".JK"):
        return True
    clean = t.replace(".JK", "")
    return clean in POPULAR_IDX_TICKERS


def is_us_ticker(ticker: Optional[str]) -> bool:
    """Returns True if ticker belongs to US or global equities."""
    if not ticker:
        return True
    return not is_idx_ticker(ticker)


# ==============================================================================
# RSS Feed Endpoints (US / Global & Indonesian IDX)
# ==============================================================================

# US & Global Feeds
YAHOO_TOP_NEWS_URL = "https://finance.yahoo.com/news/rssindex"
YAHOO_TICKER_FEED_URL = "https://feeds.finance.yahoo.com/rss/2.0/headline?s={ticker}"
CNBC_TOP_NEWS_URL = "https://search.cnbc.com/rs/search/combinedcms/view.xml?partnerId=wrss01&id=10000664"
INVESTING_STOCKS_URL = "https://www.investing.com/rss/news_25.rss"
NASDAQ_STOCKS_URL = "https://www.nasdaq.com/feed/rssoutbound?category=Stocks"
GLOBENEWSWIRE_FINANCE_URL = "https://news.google.com/rss/search?q=site:globenewswire.com+financial+OR+earnings+OR+stock&hl=en-US&gl=US&ceid=US:en"
PRNEWSWIRE_FINANCE_URL = "https://www.prnewswire.com/rss/financial-services-latest-news/financial-services-latest-news-list.rss"
BUSINESSWIRE_FINANCE_URL = "https://news.google.com/rss/search?q=site:businesswire.com+financial+OR+earnings+OR+stock&hl=en-US&gl=US&ceid=US:en"

# Indonesian IDX Feeds
KONTAN_INVESTASI_RSS_URL = "https://news.google.com/rss/search?q=site:kontan.co.id+investasi+OR+saham+OR+bursa&hl=id&gl=ID&ceid=ID:id"
DETIK_BURSA_URL = "https://finance.detik.com/bursa-dan-valas/rss"
DETIK_FINANCE_GEN_URL = "https://finance.detik.com/rss"
LIPUTAN6_BISNIS_URL = "https://feed.liputan6.com/rss/bisnis"
TEMPO_BISNIS_URL = "https://rss.tempo.co/bisnis"
CNN_INDONESIA_EKONOMI_URL = "https://www.cnnindonesia.com/ekonomi/rss"


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
    1. Explicit financial syntaxes ($TICKER, (NASDAQ: TICKER), (IDX: TICKER), (TICKER))
    2. Dynamically tracked tickers from the database (user holdings/watchlists)
    3. Curated US company name aliases (e.g. 'NVIDIA' -> 'NVDA')
    4. Curated Indonesian company name aliases (e.g. 'Bank Central Asia' -> 'BBCA')
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
            clean_ticker = ticker.strip().upper().replace(".JK", "")
            if clean_ticker and clean_ticker not in COMMON_WORD_BLACKLIST:
                if re.search(rf"\b{re.escape(clean_ticker)}\b", combined_upper):
                    found.add(clean_ticker)

    # 3. Curated Global & Indonesian Company Name Aliases
    all_aliases = {**GLOBAL_COMPANY_ALIASES, **INDONESIAN_COMPANY_ALIASES}
    for ticker, keywords in all_aliases.items():
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
    """Fetches and parses a single RSS feed over HTTP with robust browser headers."""
    headers = {
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
        "Accept": "application/rss+xml, application/xml, text/xml, */*"
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
        logger.error("Error fetching feed from %s (%s): %s", url, source_name, str(e))
        return []


async def sync_all_rss_feeds() -> int:
    """
    Ingests global news feeds from all active providers into PostgreSQL:
    - US & Global: Yahoo Finance, CNBC, Investing.com, Nasdaq, GlobeNewswire, PR Newswire, Business Wire
    - Indonesian IDX: Kontan, Detik Finance, Liputan6 Bisnis, Tempo Bisnis, CNN Indonesia Ekonomi
    Dynamically grounds incoming news against DB-tracked portfolio/watchlist tickers.
    """
    tracked_tickers = await get_tracked_tickers_from_db()
    articles: List[Dict[str, Any]] = []

    # 1. Ingest US / Global Feeds
    yahoo_articles = await fetch_rss_feed(YAHOO_TOP_NEWS_URL, "Yahoo Finance", dynamic_tickers=tracked_tickers)
    cnbc_articles = await fetch_rss_feed(CNBC_TOP_NEWS_URL, "CNBC", dynamic_tickers=tracked_tickers)
    investing_articles = await fetch_rss_feed(INVESTING_STOCKS_URL, "Investing.com", dynamic_tickers=tracked_tickers)
    nasdaq_articles = await fetch_rss_feed(NASDAQ_STOCKS_URL, "Nasdaq", dynamic_tickers=tracked_tickers)
    globenewswire_articles = await fetch_rss_feed(GLOBENEWSWIRE_FINANCE_URL, "GlobeNewswire", dynamic_tickers=tracked_tickers)
    prnewswire_articles = await fetch_rss_feed(PRNEWSWIRE_FINANCE_URL, "PR Newswire", dynamic_tickers=tracked_tickers)
    businesswire_articles = await fetch_rss_feed(BUSINESSWIRE_FINANCE_URL, "Business Wire", dynamic_tickers=tracked_tickers)

    articles.extend(yahoo_articles)
    articles.extend(cnbc_articles)
    articles.extend(investing_articles)
    articles.extend(nasdaq_articles)
    articles.extend(globenewswire_articles)
    articles.extend(prnewswire_articles)
    articles.extend(businesswire_articles)

    # 2. Ingest Indonesian IDX Feeds
    kontan_articles = await fetch_rss_feed(KONTAN_INVESTASI_RSS_URL, "Kontan", dynamic_tickers=tracked_tickers)
    detik_bursa_articles = await fetch_rss_feed(DETIK_BURSA_URL, "Detik Finance", dynamic_tickers=tracked_tickers)
    detik_gen_articles = await fetch_rss_feed(DETIK_FINANCE_GEN_URL, "Detik Finance", dynamic_tickers=tracked_tickers)
    liputan6_articles = await fetch_rss_feed(LIPUTAN6_BISNIS_URL, "Liputan6 Bisnis", dynamic_tickers=tracked_tickers)
    tempo_articles = await fetch_rss_feed(TEMPO_BISNIS_URL, "Tempo Bisnis", dynamic_tickers=tracked_tickers)
    cnn_articles = await fetch_rss_feed(CNN_INDONESIA_EKONOMI_URL, "CNN Indonesia Ekonomi", dynamic_tickers=tracked_tickers)

    articles.extend(kontan_articles)
    articles.extend(detik_bursa_articles)
    articles.extend(detik_gen_articles)
    articles.extend(liputan6_articles)
    articles.extend(tempo_articles)
    articles.extend(cnn_articles)

    if not articles:
        return 0

    return await upsert_news_articles(articles)


async def sync_ticker_news(ticker: str) -> int:
    """
    Intelligently routes and fetches news feeds strictly based on the stock's market:
    - IDX / Indonesian Stocks: Fetches ONLY from Indonesian feeds (Kontan, Detik Finance,
      Liputan6 Bisnis, Tempo Bisnis, CNN Indonesia Ekonomi, and Yahoo Finance .JK).
      Never polls US wires (Nasdaq, Investing.com, GlobeNewswire, PR Newswire, Business Wire).
    - US / Global Stocks: Fetches ONLY from US/Global feeds (Yahoo Finance, Investing.com,
      Nasdaq, GlobeNewswire, PR Newswire, Business Wire, CNBC).
      Never polls Indonesian media (Kontan, Detik Finance, Liputan6, Tempo, CNN Indonesia).
    """
    clean_ticker = ticker.strip().upper().replace(".JK", "")
    is_idx = is_idx_ticker(ticker) or is_idx_ticker(clean_ticker)

    articles: List[Dict[str, Any]] = []

    if is_idx:
        logger.info("📍 [MARKET ROUTING: IDX] Fetching Indonesian financial RSS for %s", clean_ticker)

        # 1. Kontan targeted RSS via Google News
        kontan_url = f"https://news.google.com/rss/search?q=site:kontan.co.id+{clean_ticker}&hl=id&gl=ID&ceid=ID:id"
        kontan_arts = await fetch_rss_feed(kontan_url, "Kontan", dynamic_tickers={clean_ticker})

        # 2. Detik Finance (Bursa dan Valas & General)
        detik_bursa = await fetch_rss_feed(DETIK_BURSA_URL, "Detik Finance", dynamic_tickers={clean_ticker})
        detik_gen = await fetch_rss_feed(DETIK_FINANCE_GEN_URL, "Detik Finance", dynamic_tickers={clean_ticker})

        # 3. Liputan6 Bisnis
        liputan6 = await fetch_rss_feed(LIPUTAN6_BISNIS_URL, "Liputan6 Bisnis", dynamic_tickers={clean_ticker})

        # 4. Tempo Bisnis
        tempo = await fetch_rss_feed(TEMPO_BISNIS_URL, "Tempo Bisnis", dynamic_tickers={clean_ticker})

        # 5. CNN Indonesia Ekonomi
        cnn = await fetch_rss_feed(CNN_INDONESIA_EKONOMI_URL, "CNN Indonesia Ekonomi", dynamic_tickers={clean_ticker})

        # 6. Yahoo Finance Indonesia ticker feed (.JK)
        yahoo_feed = YAHOO_TICKER_FEED_URL.format(ticker=f"{clean_ticker}.JK")
        yahoo_arts = await fetch_rss_feed(yahoo_feed, f"Yahoo Finance ({clean_ticker})", dynamic_tickers={clean_ticker})

        # Filter and ensure clean_ticker is tagged in relevant articles
        company_aliases = [kw.lower() for kw in INDONESIAN_COMPANY_ALIASES.get(clean_ticker, [])]
        raw_candidates = kontan_arts + detik_bursa + detik_gen + liputan6 + tempo + cnn + yahoo_arts

        for art in raw_candidates:
            title_lower = art["title"].lower()
            summary_lower = art.get("summary", "").lower()

            is_relevant = (
                clean_ticker in art["tickers"] or
                clean_ticker.lower() in title_lower or
                any(kw in title_lower or kw in summary_lower for kw in company_aliases) or
                art.get("source") in ["Kontan", f"Yahoo Finance ({clean_ticker})"]
            )

            if is_relevant:
                if clean_ticker not in art["tickers"]:
                    art["tickers"].append(clean_ticker)
                articles.append(art)

    else:
        logger.info("📍 [MARKET ROUTING: US/GLOBAL] Fetching US/Global financial RSS for %s", clean_ticker)

        # 1. Yahoo Finance US Ticker Feed with resilient fallback
        yahoo_feed = YAHOO_TICKER_FEED_URL.format(ticker=clean_ticker)
        yahoo_arts = await fetch_rss_feed(yahoo_feed, f"Yahoo Finance ({clean_ticker})", dynamic_tickers={clean_ticker})
        if not yahoo_arts:
            yahoo_fallback_url = f"https://news.google.com/rss/search?q=site:finance.yahoo.com+{clean_ticker}&hl=en-US&gl=US&ceid=US:en"
            yahoo_arts = await fetch_rss_feed(yahoo_fallback_url, f"Yahoo Finance ({clean_ticker})", dynamic_tickers={clean_ticker})

        # 2. Nasdaq Stocks Feed
        nasdaq_arts = await fetch_rss_feed(NASDAQ_STOCKS_URL, "Nasdaq", dynamic_tickers={clean_ticker})

        # 3. Investing.com Stocks News
        investing_arts = await fetch_rss_feed(INVESTING_STOCKS_URL, "Investing.com", dynamic_tickers={clean_ticker})

        # 4. GlobeNewswire (Targeted Ticker Search + Financials)
        gnw_ticker_url = f"https://news.google.com/rss/search?q=site:globenewswire.com+{clean_ticker}&hl=en-US&gl=US&ceid=US:en"
        globenewswire_arts = await fetch_rss_feed(gnw_ticker_url, "GlobeNewswire", dynamic_tickers={clean_ticker})

        # 5. PR Newswire
        prnewswire_arts = await fetch_rss_feed(PRNEWSWIRE_FINANCE_URL, "PR Newswire", dynamic_tickers={clean_ticker})

        # 6. Business Wire (Targeted Ticker Search + Financials)
        bw_ticker_url = f"https://news.google.com/rss/search?q=site:businesswire.com+{clean_ticker}&hl=en-US&gl=US&ceid=US:en"
        businesswire_arts = await fetch_rss_feed(bw_ticker_url, "Business Wire", dynamic_tickers={clean_ticker})

        company_aliases = [kw.lower() for kw in GLOBAL_COMPANY_ALIASES.get(clean_ticker, [])]
        raw_candidates = yahoo_arts + nasdaq_arts + investing_arts + globenewswire_arts + prnewswire_arts + businesswire_arts

        for art in raw_candidates:
            title_lower = art["title"].lower()
            summary_lower = art.get("summary", "").lower()

            is_relevant = (
                clean_ticker in art["tickers"] or
                clean_ticker.lower() in title_lower or
                any(kw in title_lower or kw in summary_lower for kw in company_aliases) or
                art.get("source") in [f"Yahoo Finance ({clean_ticker})", "GlobeNewswire", "Business Wire"]
            )

            if is_relevant:
                if clean_ticker not in art["tickers"]:
                    art["tickers"].append(clean_ticker)
                articles.append(art)

    if not articles:
        return 0

    return await upsert_news_articles(articles)
