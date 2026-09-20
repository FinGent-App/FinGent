"""
FinGent Raw RSS Extractor to Data Lake Bronze Layer
Extracts latest feeds from 12 financial portals (IDX & US) and persists raw immutable payloads into Bronze.
"""

import os
import sys
import json
import logging
from datetime import datetime, timezone
from pathlib import Path
import httpx
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(name)s: %(message)s")
logger = logging.getLogger("FinGent.BronzeExtractor")

FEEDS = [
    {"name": "Kontan", "market": "IDX", "url": "https://news.google.com/rss/search?q=site:kontan.co.id+investasi+OR+saham"},
    {"name": "Detik Finance", "market": "IDX", "url": "https://finance.detik.com/bursa-dan-valas/rss"},
    {"name": "Liputan6 Bisnis", "market": "IDX", "url": "https://feed.liputan6.com/rss/bisnis"},
    {"name": "Tempo Bisnis", "market": "IDX", "url": "https://rss.tempo.co/bisnis"},
    {"name": "Yahoo Finance US", "market": "US", "url": "https://finance.yahoo.com/news/rssindex"},
    {"name": "CNBC Markets", "market": "US", "url": "https://search.cnbc.com/rs/search/combinedcms/view.xml"},
    {"name": "Investing.com", "market": "US", "url": "https://www.investing.com/rss/news_25.rss"},
    {"name": "Nasdaq Stocks", "market": "US", "url": "https://www.nasdaq.com/feed/rssoutbound?category=Stocks"},
]


def extract_rss_to_bronze(market_filter: str = "ALL", limit_feeds: int = 10):
    now = datetime.now(timezone.utc)
    year = now.strftime("%Y")
    month = now.strftime("%m")
    day = now.strftime("%d")

    target_feeds = [f for f in FEEDS if market_filter == "ALL" or f["market"] == market_filter]
    logger.info("Extracting %d feeds for market '%s' to Bronze Lake...", len(target_feeds), market_filter)

    bronze_out_dir = Path(f"data/lakehouse/bronze/news/year={year}/month={month}/day={day}")
    bronze_out_dir.mkdir(parents=True, exist_ok=True)

    extracted_count = 0

    with httpx.Client(timeout=15.0, follow_redirects=True) as client:
        for feed in target_feeds[:limit_feeds]:
            try:
                resp = client.get(feed["url"], headers={"User-Agent": "Mozilla/5.0 (FinGent Data Engineer Lakehouse)"})
                if resp.status_code != 200:
                    continue

                # Parse XML
                root = ET.fromstring(resp.content)
                items = root.findall(".//item")
                parsed_items = []

                for it in items[:15]:
                    title_elem = it.find("title")
                    link_elem = it.find("link")
                    desc_elem = it.find("description")
                    pub_elem = it.find("pubDate")

                    parsed_items.append({
                        "source": feed["name"],
                        "market": feed["market"],
                        "title": title_elem.text if title_elem is not None else "",
                        "url": link_elem.text if link_elem is not None else "",
                        "summary": desc_elem.text if desc_elem is not None else "",
                        "published_at": pub_elem.text if pub_elem is not None else now.isoformat(),
                        "extracted_at": now.isoformat()
                    })

                if parsed_items:
                    safe_name = feed["name"].lower().replace(" ", "_")
                    filename = f"{safe_name}_{int(now.timestamp())}.json"
                    file_path = bronze_out_dir / filename
                    with open(file_path, "w", encoding="utf-8") as f:
                        json.dump(parsed_items, f, indent=2)

                    extracted_count += len(parsed_items)
                    logger.info("Saved %d raw items from %s to Bronze at %s", len(parsed_items), feed["name"], file_path)

            except Exception as e:
                logger.warning("Failed to extract %s: %s", feed["name"], str(e))

    logger.info("✅ Total %d raw articles ingested into Bronze Lakehouse.", extracted_count)
    return extracted_count


if __name__ == "__main__":
    market = "ALL"
    if len(sys.argv) > 1 and "--market" in sys.argv:
        idx = sys.argv.index("--market")
        if idx + 1 < len(sys.argv):
            market = sys.argv[idx + 1]
    extract_rss_to_bronze(market)
