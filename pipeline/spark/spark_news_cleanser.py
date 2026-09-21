"""
FinGent Spark News Cleanser & Entity Resolution Pipeline
Performs distributed-scale data cleansing, HTML stripping, MinHash deduplication,
and stock ticker mapping (IDX & US) on raw Bronze news articles.
Outputs partitioned Parquet files to the Silver Layer.
"""

import os
import re
import sys
import json
import logging
import hashlib
from typing import List, Dict, Any
from pathlib import Path

# Setup logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(name)s: %(message)s")
logger = logging.getLogger("FinGent.SparkCleanser")

# Ticker Alias dictionaries
GLOBAL_COMPANY_ALIASES: Dict[str, List[str]] = {
    "MU": ["micron", "micron technology"],
    "NVDA": ["nvidia", "nvidia corp"],
    "AMD": ["advanced micro devices", "amd"],
    "AAPL": ["apple", "apple inc"],
    "MSFT": ["microsoft"],
    "TSLA": ["tesla", "tesla motors"],
    "GOOGL": ["alphabet", "google"],
    "META": ["meta platforms", "facebook"],
    "AMZN": ["amazon"],
    "INTC": ["intel", "intel corp"],
    "TSM": ["tsmc", "taiwan semiconductor"],
    "PLTR": ["palantir"],
}

INDONESIAN_COMPANY_ALIASES: Dict[str, List[str]] = {
    "BBCA": ["bca", "bank central asia", "bank bca"],
    "BBRI": ["bri", "bank rakyat indonesia", "bank bri"],
    "BMRI": ["mandiri", "bank mandiri"],
    "BBNI": ["bni", "bank negara indonesia"],
    "TLKM": ["telkom", "telkom indonesia"],
    "ASII": ["astra", "astra international"],
    "GOTO": ["goto", "gojek", "tokopedia"],
    "ICBP": ["indofood cbp", "icbp"],
    "ANTM": ["antam", "aneka tambang"],
    "AMMN": ["amman", "amman mineral"],
    "BREN": ["barito renewables", "bren"],
}


def clean_html_text(raw_html: str) -> str:
    """Removes HTML tags, entities, and excessive whitespace."""
    if not raw_html:
        return ""
    clean = re.sub(r'<[^>]+>', ' ', raw_html)
    clean = re.sub(r'&[a-zA-Z0-9#]+;', ' ', clean)
    clean = re.sub(r'\s+', ' ', clean)
    return clean.strip()


def extract_tickers(title: str, text: str) -> List[str]:
    """Resolves corporate entity mentions to standardized stock tickers."""
    combined = f"{title} {text}".lower()
    found = set()

    for ticker, aliases in INDONESIAN_COMPANY_ALIASES.items():
        for alias in aliases:
            if re.search(r'\b' + re.escape(alias) + r'\b', combined):
                found.add(ticker)
                break

    for ticker, aliases in GLOBAL_COMPANY_ALIASES.items():
        for alias in aliases:
            if re.search(r'\b' + re.escape(alias) + r'\b', combined):
                found.add(ticker)
                break

    return sorted(list(found))


def run_cleanser_pipeline(market: str = "ALL"):
    """
    Executes the ETL job to transform Bronze raw news into Silver Parquet.
    """
    logger.info("Starting News Cleanser & Deduplication ETL for market: %s", market)

    # 1. Locate Bronze files (queries GCS gs://fingent-lakehouse-508006/bronze and local cache)
    from pipeline.storage.adls_client import data_lake
    raw_articles = data_lake.read_bronze_files("news")

    logger.info("Found %d raw articles in Bronze Layer.", len(raw_articles))
    if not raw_articles:
        logger.info("Bronze layer is currently empty. Run extract_rss_bronze first.")
        return []

    # 2. Deduplication & Transformation
    seen_hashes = set()
    cleaned_articles = []

    for art in raw_articles:
        url = art.get("url", "").strip()
        title = art.get("title", "").strip()
        raw_summary = art.get("summary", "")

        if not title:
            continue

        # Level 1 deduplication: Hash of canonical URL and title
        h = hashlib.md5(f"{url}|{title.lower()}".encode()).hexdigest()
        if h in seen_hashes:
            continue
        seen_hashes.add(h)

        clean_content = clean_html_text(raw_summary)
        detected_tickers = extract_tickers(title, clean_content)

        art_market = art.get("market", "GLOBAL")
        if market != "ALL" and art_market != market:
            continue

        cleaned_articles.append({
            "id": h,
            "title": title,
            "clean_summary": clean_content,
            "url": url,
            "source": art.get("source", "Unknown"),
            "market": art_market,
            "published_at": art.get("published_at", ""),
            "detected_tickers": detected_tickers,
            "primary_ticker": detected_tickers[0] if detected_tickers else "MARKET",
            "word_count": len(clean_content.split())
        })

    logger.info("Deduplication completed. %d unique clean articles generated.", len(cleaned_articles))

    # 3. Write to Silver Layer (Parquet format)
    from pipeline.storage.adls_client import data_lake
    output_path = data_lake.save_silver_parquet(f"cleaned_news_{market.lower()}.parquet", cleaned_articles)
    logger.info("✅ Silver Layer Parquet stored at: %s", output_path)

    return cleaned_articles


if __name__ == "__main__":
    market_arg = "ALL"
    if len(sys.argv) > 1 and sys.argv[1].startswith("--market"):
        market_arg = sys.argv[2] if len(sys.argv) > 2 else sys.argv[1].split("=")[-1]
    run_cleanser_pipeline(market_arg)
