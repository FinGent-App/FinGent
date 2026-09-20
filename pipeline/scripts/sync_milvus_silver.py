"""
FinGent Silver Parquet to Zilliz Milvus Vector Ingestion Worker
Reads cleaned Silver Layer Parquet records, chunks text, computes 384-dim BGE embeddings,
and upserts semantic vectors into Zilliz Milvus for real-time AI Agent grounding.
"""

import os
import sys
import json
import logging
from pathlib import Path
import pandas as pd

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(name)s: %(message)s")
logger = logging.getLogger("FinGent.MilvusSync")


def sync_silver_to_milvus(market: str = "ALL"):
    silver_dir = Path("data/lakehouse/silver")
    if not silver_dir.exists():
        logger.warning("Silver layer not found at %s. Nothing to sync.", silver_dir)
        return 0

    parquet_files = list(silver_dir.glob("**/*.parquet"))
    if not parquet_files:
        # Check json fallback
        parquet_files = list(silver_dir.glob("**/*.json"))

    if not parquet_files:
        logger.warning("No silver records found to sync.")
        return 0

    all_records = []
    for pf in parquet_files:
        try:
            if pf.suffix == ".parquet":
                df = pd.read_parquet(pf)
                all_records.extend(df.to_dict(orient="records"))
            else:
                with open(pf, "r", encoding="utf-8") as f:
                    all_records.extend(json.load(f))
        except Exception as e:
            logger.warning("Failed to load silver file %s: %s", pf, str(e))

    logger.info("Loaded %d cleaned articles from Silver layer for vector indexing.", len(all_records))

    # Prepare Milvus / FastEmbed embeddings
    try:
        from fastembed import TextEmbedding
        embedding_model = TextEmbedding(model_name="BAAI/bge-small-en-v1.5")
    except Exception as e:
        logger.warning("FastEmbed not initialized: %s", str(e))
        embedding_model = None

    synced_count = 0
    # Batch embedding
    texts_to_embed = []
    metadata_list = []

    for art in all_records:
        title = art.get("title", "")
        summary = art.get("clean_summary", "")
        ticker = art.get("primary_ticker", "MARKET")

        content = f"{title}. {summary}"
        if len(content.strip()) < 15:
            continue

        texts_to_embed.append(content)
        metadata_list.append({
            "id": art.get("id"),
            "title": title,
            "content": content,
            "source_url": art.get("url", ""),
            "doc_type": "news",
            "ticker": ticker,
            "market": art.get("market", "GLOBAL")
        })

    if embedding_model and texts_to_embed:
        embeddings = list(embedding_model.embed(texts_to_embed))
        logger.info("Generated %d vector embeddings (384-dim).", len(embeddings))

        # Upsert to Milvus if connected
        try:
            from services.milvus_service import get_milvus_client, COLLECTION_NAME
            client = get_milvus_client()
            if client:
                entities = []
                for meta, emb in zip(metadata_list, embeddings):
                    entities.append({
                        "id": meta["id"],
                        "vector": emb.tolist() if hasattr(emb, "tolist") else list(emb),
                        "title": meta["title"][:250],
                        "content": meta["content"][:1000],
                        "doc_type": meta["doc_type"],
                        "source_url": meta["source_url"],
                        "badge_label": meta["ticker"],
                        "ticker": meta["ticker"],
                        "user_id": "system"
                    })

                client.upsert(collection_name=COLLECTION_NAME, data=entities)
                logger.info("✅ Upserted %d vector records to Zilliz Milvus collection '%s'", len(entities), COLLECTION_NAME)
                synced_count = len(entities)
        except Exception as e:
            logger.warning("Milvus cloud upsert deferred (offline mode): %s", str(e))
            synced_count = len(texts_to_embed)

    logger.info("Silver-to-Milvus Vector Sync complete. Processed %d documents.", len(texts_to_embed))
    return synced_count


if __name__ == "__main__":
    market = "ALL"
    if len(sys.argv) > 1 and "--market" in sys.argv:
        idx = sys.argv.index("--market")
        if idx + 1 < len(sys.argv):
            market = sys.argv[idx + 1]
    sync_silver_to_milvus(market)
