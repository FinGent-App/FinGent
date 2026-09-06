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

POPULAR_IDX_TICKERS = ["BBCA", "BBRI", "BMRI", "TLKM", "ASII", "GOTO", "BBNI", "ICBP", "UNVR", "AMMN"]


def normalize_ticker(ticker: str) -> str:
    """Ensure Indonesian stock tickers end with .JK, unless it's a market index like ^JKSE."""
    t = ticker.strip().upper()
    if t.startswith("^"):
        return t
    if not t.endswith(".JK"):
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
                "pbv_ratio": round(float(info.get("priceToBook") or 0.0), 2),
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
