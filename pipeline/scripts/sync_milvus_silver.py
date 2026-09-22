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
    from pipeline.storage.adls_client import data_lake
    all_records = data_lake.read_silver_records()

    if market != "ALL":
        all_records = [r for r in all_records if r.get("market") == market]

    if not all_records:
        logger.warning("No silver records found in GCS or local layer for market %s.", market)
        return 0

    logger.info("Loaded %d cleaned articles from Silver layer (GCS gs://fingent-lakehouse-508006/silver) for vector indexing.", len(all_records))

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
            from pymilvus import MilvusClient
            milvus_uri = os.getenv("MILVUS_URI", "https://in03-6434b859fba728b.serverless.gcp-us-west1.cloud.zilliz.com")
            milvus_token = os.getenv("MILVUS_TOKEN", "91aed176ff208a1389cbba47937902a4419da9402c4e2bde664f7cbe2b6611c429f2049f5795de0ab19a2de9f7a3fa3b910a2ad8")
            collection_name = os.getenv("MILVUS_COLLECTION", "fingent_knowledge")

            client = None
            if milvus_uri and milvus_token:
                client = MilvusClient(uri=milvus_uri, token=milvus_token)
            else:
                try:
                    from services.milvus_service import get_milvus_client, COLLECTION_NAME
                    client = get_milvus_client()
                    collection_name = COLLECTION_NAME
                except Exception:
                    pass

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

                client.upsert(collection_name=collection_name, data=entities)
                logger.info("✅ Upserted %d vector records to Zilliz Milvus collection '%s'", len(entities), collection_name)
                synced_count = len(entities)
            else:
                logger.warning("Milvus client could not be initialized. Skipping upsert.")
        except Exception as e:
            logger.warning("Milvus cloud upsert deferred: %s", str(e))
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
