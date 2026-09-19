#!/usr/bin/env python3
"""
Test script to verify market-based RSS routing for US vs IDX stocks.
"""
import sys
import asyncio
from services.rss_ingestion_service import (
    is_idx_ticker,
    is_us_ticker,
    extract_tickers,
    fetch_rss_feed,
    INDONESIAN_SOURCES,
    US_GLOBAL_SOURCES
)

def test_market_classification():
    print("Testing market classification...")
    # IDX checks
    assert is_idx_ticker("BBCA"), "BBCA should be recognized as IDX"
    assert is_idx_ticker("BBCA.JK"), "BBCA.JK should be recognized as IDX"
    assert is_idx_ticker("GOTO"), "GOTO should be recognized as IDX"
    assert is_idx_ticker("TLKM"), "TLKM should be recognized as IDX"
    assert is_idx_ticker("BREN.JK"), "BREN.JK should be recognized as IDX"
    assert not is_us_ticker("BBCA"), "BBCA should not be US"

    # US checks
    assert is_us_ticker("AAPL"), "AAPL should be US"
    assert is_us_ticker("NVDA"), "NVDA should be US"
    assert is_us_ticker("MU"), "MU should be US"
    assert is_us_ticker("MSFT"), "MSFT should be US"
    assert not is_idx_ticker("AAPL"), "AAPL should not be IDX"
    print("✅ Market classification passed.")

def test_ticker_extraction():
    print("\nTesting ticker extraction in English and Indonesian text...")
    idx_text = "Bank Central Asia catat rekor laba bersih di kuartal kedua, ditopang pertumbuhan kredit."
    tickers_idx = extract_tickers("Kinerja Bank Central Asia", idx_text)
    assert "BBCA" in tickers_idx, f"Expected BBCA in {tickers_idx}"

    us_text = "Micron Technology raises its revenue forecast as AI demand surges for HBM memory."
    tickers_us = extract_tickers("Micron Reports Q3", us_text)
    assert "MU" in tickers_us, f"Expected MU in {tickers_us}"
    print("✅ Ticker extraction passed.")

async def test_targeted_rss_sources():
    print("\nTesting targeted feeds for IDX stock (BBCA)...")
    kontan_url = "https://news.google.com/rss/search?q=site:kontan.co.id+BBCA&hl=id&gl=ID&ceid=ID:id"
    kontan_arts = await fetch_rss_feed(kontan_url, "Kontan")
    print(f"Kontan BBCA articles found: {len(kontan_arts)}")
    assert len(kontan_arts) > 0, "Expected Kontan to return articles for BBCA"
    print(f"Sample Kontan headline: {kontan_arts[0]['title']}")

    print("\nTesting targeted feeds for US stock (NVDA)...")
    gnw_url = "https://news.google.com/rss/search?q=site:globenewswire.com+NVDA&hl=en-US&gl=US&ceid=US:en"
    gnw_arts = await fetch_rss_feed(gnw_url, "GlobeNewswire")
    print(f"GlobeNewswire NVDA articles found: {len(gnw_arts)}")
    assert len(gnw_arts) > 0, "Expected GlobeNewswire to return articles for NVDA"
    print(f"Sample GlobeNewswire headline: {gnw_arts[0]['title']}")

    bw_url = "https://news.google.com/rss/search?q=site:businesswire.com+NVDA&hl=en-US&gl=US&ceid=US:en"
    bw_arts = await fetch_rss_feed(bw_url, "Business Wire")
    print(f"Business Wire NVDA articles found: {len(bw_arts)}")
    assert len(bw_arts) > 0, "Expected Business Wire to return articles for NVDA"
    print(f"Sample Business Wire headline: {bw_arts[0]['title']}")
    print("✅ Targeted market feeds verified successfully.")

if __name__ == "__main__":
    test_market_classification()
    test_ticker_extraction()
    asyncio.run(test_targeted_rss_sources())
