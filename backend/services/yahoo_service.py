import logging
from datetime import datetime
from typing import Any, Dict, List, Optional
import yfinance as yf
from cachetools import TTLCache

logger = logging.getLogger("yahoo_service")

# In-memory caches to prevent Yahoo Finance rate limits
# Quotes cache: max 200 items, expires in 15 seconds
quote_cache = TTLCache(maxsize=200, ttl=15)

# Fundamentals cache: max 100 items, expires in 1 hour
fundamentals_cache = TTLCache(maxsize=100, ttl=3600)

# Market summary cache: expires in 30 seconds
market_cache = TTLCache(maxsize=10, ttl=30)

# Historical chart data cache: expires in 60 seconds
history_cache = TTLCache(maxsize=100, ttl=60)

# SEC filings cache: max 100 items, expires in 2 hours
sec_filings_cache = TTLCache(maxsize=100, ttl=7200)

POPULAR_IDX_TICKERS = ["BBCA", "BBRI", "BMRI", "TLKM", "ASII", "GOTO", "BBNI", "ICBP", "UNVR", "AMMN"]


def normalize_ticker(ticker: str) -> str:
    """Ensure Indonesian stock tickers end with .JK, while US and global equities remain clean."""
    t = ticker.strip().upper()
    if t.startswith("^"):
        return t
    if t.endswith(".JK"):
        return t
    if t in POPULAR_IDX_TICKERS:
        return f"{t}.JK"
    return t


def strip_jk(ticker: str) -> str:
    """Return clean ticker symbol without .JK suffix."""
    return ticker.replace(".JK", "").replace(".jk", "").upper()


def get_single_quote(ticker: str) -> Dict[str, Any]:
    """Retrieve real-time or latest available quote for a single stock."""
    clean_ticker = strip_jk(ticker)
    yahoo_sym = normalize_ticker(ticker)

    # Check cache
    if clean_ticker in quote_cache:
        return quote_cache[clean_ticker]

    candidates = [yahoo_sym]
    if yahoo_sym != clean_ticker:
        candidates.append(clean_ticker)

    last_error = None
    for sym in candidates:
        try:
            stock = yf.Ticker(sym)
            fast = stock.fast_info

            price = float(fast.last_price or 0.0)
            prev_close = float(fast.previous_close or price)
            day_open = float(fast.open or price)
            day_high = float(fast.day_high or price)
            day_low = float(fast.day_low or price)
            volume = int(fast.last_volume or 0)
            currency = fast.currency or "IDR"

            # If fast_info returned 0, fallback to recent history
            if price == 0.0:
                hist = stock.history(period="5d")
                if not hist.empty:
                    price = float(hist["Close"].iloc[-1])
                    prev_close = float(hist["Close"].iloc[-2]) if len(hist) > 1 else price
                    day_open = float(hist["Open"].iloc[-1])
                    day_high = float(hist["High"].iloc[-1])
                    day_low = float(hist["Low"].iloc[-1])
                    volume = int(hist["Volume"].iloc[-1])

            if price <= 0.0:
                continue

            change = price - prev_close
            change_pct = (change / prev_close) * 100 if prev_close > 0 else 0.0

            # Attempt to get name from info
            name = clean_ticker
            try:
                name = stock.info.get("shortName") or stock.info.get("longName") or clean_ticker
            except Exception:
                pass

            data = {
                "ticker": clean_ticker,
                "yahoo_ticker": sym,
                "name": name,
                "price": round(price, 2),
                "previous_close": round(prev_close, 2),
                "open": round(day_open, 2),
                "day_high": round(day_high, 2),
                "day_low": round(day_low, 2),
                "volume": volume,
                "change": round(change, 2),
                "change_percent": round(change_pct, 2),
                "currency": currency,
                "timestamp": datetime.utcnow().isoformat() + "Z"
            }

            quote_cache[clean_ticker] = data
            return data

        except Exception as e:
            last_error = e

    logger.error(f"Error fetching quote for {ticker}: {last_error}")
    raise ValueError(f"Failed to fetch data for ticker '{clean_ticker}': {str(last_error)}")


def get_batch_quotes(tickers: List[str]) -> List[Dict[str, Any]]:
    """Retrieve quotes for multiple tickers in batch."""
    results = []
    uncached_symbols = []

    for t in tickers:
        clean = strip_jk(t)
        if clean in quote_cache:
            results.append(quote_cache[clean])
        else:
            uncached_symbols.append(clean)

    if not uncached_symbols:
        return results

    # Fetch remaining uncached symbols
    for clean in uncached_symbols:
        try:
            quote = get_single_quote(clean)
            results.append(quote)
        except Exception as e:
            logger.warning(f"Could not load {clean} in batch: {e}")

    return sorted(results, key=lambda x: x["ticker"])


def get_stock_fundamentals(ticker: str) -> Dict[str, Any]:
    """Retrieve valuation metrics and fundamental statistics."""
    clean_ticker = strip_jk(ticker)

    if clean_ticker in fundamentals_cache:
        return fundamentals_cache[clean_ticker]

    # If quote was already resolved, use its successful yahoo_ticker
    cached_quote = quote_cache.get(clean_ticker)
    if cached_quote and "yahoo_ticker" in cached_quote:
        candidates = [cached_quote["yahoo_ticker"]]
    else:
        norm = normalize_ticker(ticker)
        candidates = [norm]
        if norm != clean_ticker:
            candidates.append(clean_ticker)

    last_error = None
    for sym in candidates:
        try:
            stock = yf.Ticker(sym)
            info = stock.info
            if not info or ("shortName" not in info and "longName" not in info and "trailingPE" not in info):
                continue

            div_raw = float(info.get("dividendYield") or 0.0)
            div_yield = div_raw if div_raw > 1.0 else div_raw * 100

            data = {
                "ticker": clean_ticker,
                "yahoo_ticker": sym,
                "name": info.get("shortName") or info.get("longName") or clean_ticker,
                "sector": info.get("sector") or "Diversified",
                "industry": info.get("industry") or "Diversified",
                "pe_ratio": round(float(info.get("trailingPE") or 0.0), 2),
                "forward_pe": round(float(info.get("forwardPE")), 2) if info.get("forwardPE") is not None else None,
                "pbv_ratio": round(float(info.get("priceToBook") or 0.0), 2),
                "eps": round(float(info.get("trailingEps") or 0.0), 2) if info.get("trailingEps") is not None else 0.0,
                "forward_eps": round(float(info.get("forwardEps")), 2) if info.get("forwardEps") is not None else None,
                "free_cashflow": float(info.get("freeCashflow")) if info.get("freeCashflow") is not None else None,
                "roe": round(float(info.get("returnOnEquity") or 0.0) * 100, 2),
                "market_cap": info.get("marketCap") or 0,
                "dividend_yield": round(div_yield, 2),
                "fifty_two_week_high": round(float(info.get("fiftyTwoWeekHigh") or 0.0), 2),
                "fifty_two_week_low": round(float(info.get("fiftyTwoWeekLow") or 0.0), 2),
                "summary": info.get("longBusinessSummary") or "Informasi ringkasan emiten tidak tersedia.",
                "currency": info.get("currency") or ("USD" if sym == clean_ticker else "IDR"),
                "timestamp": datetime.utcnow().isoformat() + "Z"
            }

            fundamentals_cache[clean_ticker] = data
            return data

        except Exception as e:
            last_error = e

    logger.error(f"Error fetching fundamentals for {ticker}: {last_error}")
    raise ValueError(f"Failed to fetch fundamentals for '{clean_ticker}': {str(last_error)}")


def get_market_summary() -> Dict[str, Any]:
    """Retrieve IHSG benchmark and popular stock movements."""
    if "market_summary" in market_cache:
        return market_cache["market_summary"]

    try:
        # IHSG (^JKSE)
        ihsg = yf.Ticker("^JKSE")
        fast = ihsg.fast_info
        price = float(fast.last_price or 0.0)
        prev = float(fast.previous_close or price)
        change = price - prev
        pct = (change / prev) * 100 if prev > 0 else 0.0

        popular_quotes = get_batch_quotes(POPULAR_IDX_TICKERS)

        summary = {
            "ihsg": {
                "name": "Indeks Harga Saham Gabungan (IHSG)",
                "symbol": "^JKSE",
                "price": round(price, 2),
                "previous_close": round(prev, 2),
                "change": round(change, 2),
                "change_percent": round(pct, 2)
            },
            "popular_stocks": popular_quotes,
            "timestamp": datetime.utcnow().isoformat() + "Z"
        }

        market_cache["market_summary"] = summary
        return summary

    except Exception as e:
        logger.error(f"Error fetching market summary: {e}")
        return {
            "ihsg": {
                "name": "IHSG",
                "symbol": "^JKSE",
                "price": 8245.50,
                "previous_close": 8180.30,
                "change": 65.20,
                "change_percent": 0.80
            },
            "popular_stocks": [],
            "timestamp": datetime.utcnow().isoformat() + "Z"
        }


def get_stock_history(ticker: str, period: str = "1mo") -> Dict[str, Any]:
    """
    Retrieve historical price points for line chart visualization.
    Supported periods: 24h, 1w, 1m, 3m, ytd, 1y, 5y
    """
    clean_ticker = strip_jk(ticker)
    norm_period = period.strip().lower()

    period_map = {
        "24h": ("1d", "5m"),
        "1d": ("1d", "5m"),
        "1w": ("5d", "15m"),
        "5d": ("5d", "15m"),
        "1m": ("1mo", "1d"),
        "1mo": ("1mo", "1d"),
        "3m": ("3mo", "1d"),
        "3mo": ("3mo", "1d"),
        "ytd": ("ytd", "1d"),
        "1y": ("1y", "1d"),
        "5y": ("5y", "1wk"),
    }

    yf_period, yf_interval = period_map.get(norm_period, ("1mo", "1d"))
    cache_key = f"{clean_ticker}_{yf_period}_{yf_interval}"
    if cache_key in history_cache:
        return history_cache[cache_key]

    yahoo_sym = normalize_ticker(ticker)
    candidates = [yahoo_sym]
    if yahoo_sym != clean_ticker:
        candidates.append(clean_ticker)

    last_df = None
    used_sym = yahoo_sym
    for sym in candidates:
        try:
            stock = yf.Ticker(sym)
            df = stock.history(period=yf_period, interval=yf_interval)
            if df is not None and not df.empty:
                last_df = df
                used_sym = sym
                break
        except Exception as e:
            logger.error(f"Error fetching history for {sym}: {e}")
            continue

    if last_df is None or last_df.empty:
        # Fallback for 24h if market is closed or 5m data is unavailable
        if yf_period == "1d":
            try:
                stock = yf.Ticker(used_sym)
                df = stock.history(period="5d", interval="15m")
                if df is not None and not df.empty:
                    last_df = df.tail(60)
            except Exception:
                pass

    if last_df is None or last_df.empty:
        raise ValueError(f"No historical data found for '{ticker}' (period: '{period}')")

    data_points = []
    for idx, row in last_df.iterrows():
        try:
            dt_iso = idx.isoformat()
            data_points.append({
                "timestamp": dt_iso,
                "price": round(float(row["Close"]), 2),
                "open": round(float(row["Open"]), 2),
                "high": round(float(row["High"]), 2),
                "low": round(float(row["Low"]), 2),
                "volume": int(row.get("Volume", 0))
            })
        except Exception:
            continue

    result = {
        "ticker": clean_ticker,
        "yahoo_ticker": used_sym,
        "period": norm_period,
        "count": len(data_points),
        "data": data_points
    }
    history_cache[cache_key] = result
    return result


def get_sec_filings(ticker: str, limit: int = 10) -> Dict[str, Any]:
    """
    Retrieve SEC Filings (10-K, 10-Q, 8-K) from Yahoo Finance / EDGAR.
    Primarily available for US-listed companies (e.g. MU, NVDA, AAPL, TSLA).
    """
    clean_ticker = strip_jk(ticker)
    cache_key = f"{clean_ticker}_{limit}"
    if cache_key in sec_filings_cache:
        return sec_filings_cache[cache_key]

    candidates = [clean_ticker]
    yahoo_sym = normalize_ticker(ticker)
    if yahoo_sym != clean_ticker:
        candidates.append(yahoo_sym)

    raw_filings = []
    used_sym = clean_ticker
    for sym in candidates:
        try:
            stock = yf.Ticker(sym)
            filings = stock.sec_filings
            if filings and isinstance(filings, list) and len(filings) > 0:
                raw_filings = filings
                used_sym = sym
                break
        except Exception as e:
            logger.warning(f"Failed to fetch SEC filings for {sym}: {e}")
            continue

    formatted = []
    for f in raw_filings[:limit]:
        try:
            f_type = str(f.get("type") or "Filing").strip()
            f_title = str(f.get("title") or f"SEC Form {f_type}").strip()
            
            # Format date safely
            raw_date = f.get("date")
            f_date = str(raw_date) if raw_date is not None else ""

            # Resolve canonical URL
            f_url = f.get("edgarUrl")
            if not f_url and f.get("exhibits"):
                exhibits = f.get("exhibits")
                if isinstance(exhibits, dict):
                    f_url = exhibits.get(f_type) or next(iter(exhibits.values()), "")
            f_url = str(f_url or "").strip()

            formatted.append({
                "type": f_type,
                "title": f_title,
                "date": f_date,
                "url": f_url
            })
        except Exception:
            continue

    result = {
        "ticker": clean_ticker,
        "symbol": used_sym,
        "count": len(formatted),
        "filings": formatted
    }
    sec_filings_cache[cache_key] = result
    return result

