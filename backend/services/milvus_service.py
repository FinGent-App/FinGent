import os
import hashlib
import logging
from typing import List, Dict, Any, Optional
from dotenv import load_dotenv

load_dotenv()

logger = logging.getLogger("FinGent.Milvus")

MILVUS_URI = os.getenv("MILVUS_URI", "")
MILVUS_TOKEN = os.getenv("MILVUS_TOKEN", "")
COLLECTION_NAME = "fingent_knowledge"
EMBEDDING_DIM = 384

_milvus_client = None
_embedding_model = None


def get_embedding_model():
    """
    Returns the FastEmbed text embedding model (bge-small-en-v1.5, 384 dimensions).
    Runs fast and locally on CPU without external API keys.
    """
    global _embedding_model
    if _embedding_model is not None:
        return _embedding_model

    try:
        from fastembed import TextEmbedding
        logger.info("Initializing FastEmbed embedding model (bge-small-en-v1.5)...")
        _embedding_model = TextEmbedding(model_name="BAAI/bge-small-en-v1.5")
        logger.info("✅ FastEmbed embedding model loaded successfully.")
        return _embedding_model
    except Exception as e:
        logger.error("❌ Failed to initialize FastEmbed: %s", str(e))
        return None


def embed_texts(texts: List[str]) -> List[List[float]]:
    """
    Embeds a list of texts into 384-dimensional dense vectors.
    """
    model = get_embedding_model()
    if model is None:
        logger.warning("Embedding model unavailable, falling back to zero vectors.")
        return [[0.0] * EMBEDDING_DIM for _ in texts]

    try:
        embeddings = list(model.embed(texts))
        return [emb.tolist() if hasattr(emb, "tolist") else list(emb) for emb in embeddings]
    except Exception as e:
        logger.error("Error during embedding generation: %s", str(e))
        return [[0.0] * EMBEDDING_DIM for _ in texts]


def get_milvus_client():
    """
    Returns the singleton MilvusClient connected to Zilliz Cloud or local Milvus.
    """
    global _milvus_client
    if _milvus_client is not None:
        return _milvus_client

    if not MILVUS_URI or not MILVUS_TOKEN:
        logger.warning("MILVUS_URI or MILVUS_TOKEN not set in environment.")
        return None

    try:
        from pymilvus import MilvusClient
        _milvus_client = MilvusClient(
            uri=MILVUS_URI,
            token=MILVUS_TOKEN
        )
        logger.info("✅ Connected to Zilliz Cloud Milvus at %s", MILVUS_URI)
        init_collection()
        return _milvus_client
    except Exception as e:
        logger.error("❌ Failed to connect to Zilliz Cloud: %s", str(e))
        _milvus_client = None
        return None


def init_collection():
    """
    Initializes the fingent_knowledge collection with auto-indexing.
    """
    global _milvus_client
    if _milvus_client is None:
        return

    try:
        if not _milvus_client.has_collection(COLLECTION_NAME):
            logger.info("Creating Milvus collection '%s' (dim=%d)...", COLLECTION_NAME, EMBEDDING_DIM)
            _milvus_client.create_collection(
                collection_name=COLLECTION_NAME,
                dimension=EMBEDDING_DIM,
                metric_type="COSINE",
                id_type="string",
                max_length=128,
                auto_id=False
            )
            logger.info("✅ Collection '%s' successfully created on Zilliz Cloud.", COLLECTION_NAME)
        else:
            logger.info("Collection '%s' already exists on Zilliz Cloud.", COLLECTION_NAME)
    except Exception as e:
        logger.error("Failed to initialize Milvus collection: %s", str(e))


def sync_portfolio_to_milvus(user_id: str, holdings: List[Dict[str, Any]]) -> int:
    """
    Upserts user portfolio holdings and calculated P/L into Zilliz Cloud.
    """
    client = get_milvus_client()
    if client is None or not holdings:
        return 0

    entities = []
    texts_to_embed = []

    for h in holdings:
        ticker = str(h.get("ticker", "")).strip().upper()
        name = h.get("name", ticker)
        shares = h.get("shares", 0)
        price_per_share = h.get("price_per_share", 0.0)
        invested_amount = h.get("invested_amount", shares * price_per_share)
        sector = h.get("sector", "Stock")

        text = (
            f"User {user_id} Portfolio Holding: Stock {ticker} ({name}). "
            f"Total Shares Owned: {shares} shares. "
            f"Average Purchase Price: ${price_per_share:,.2f}. "
            f"Total Invested Capital: ${invested_amount:,.2f}. "
            f"Industry Sector: {sector}."
        )
        texts_to_embed.append(text)

        entity_id = f"pf_{user_id}_{ticker.lower()}"
        entities.append({
            "id": entity_id,
            "doc_type": "portfolio",
            "badge_label": "Portofolio & P/L",
            "ticker": ticker,
            "user_id": user_id,
            "title": f"Posisi Portofolio: {ticker} ({shares} lembar)",
            "content": text,
            "source_url": ""
        })

    vectors = embed_texts(texts_to_embed)
    for i, vec in enumerate(vectors):
        entities[i]["vector"] = vec

    try:
        res = client.upsert(collection_name=COLLECTION_NAME, data=entities)
        logger.info("✅ Synced %d portfolio holdings to Zilliz Cloud for user %s", len(entities), user_id)
        return len(entities)
    except Exception as e:
        logger.error("Failed to upsert portfolio to Milvus: %s", str(e))
        return 0


def sync_sec_to_milvus(ticker: str, filings: List[Dict[str, Any]]) -> int:
    """
    Upserts company SEC Filings (10-K, 10-Q, 8-K) into Zilliz Cloud.
    """
    client = get_milvus_client()
    if client is None or not filings:
        return 0

    clean_ticker = ticker.strip().upper()
    entities = []
    texts_to_embed = []

    for f in filings:
        filing_type = f.get("type", "SEC Report")
        title = f.get("title", f"{clean_ticker} SEC Filing")
        date = f.get("date", "")
        url = f.get("url", "")

        text = (
            f"U.S. SEC Regulatory Filing for {clean_ticker}: Form {filing_type} - {title}. "
            f"Filing Date: {date}. "
            f"Official disclosure report filed with the United States Securities and Exchange Commission (EDGAR)."
        )
        texts_to_embed.append(text)

        clean_type = filing_type.replace("/", "_").replace(" ", "_").lower()
        entity_id = f"sec_{clean_ticker.lower()}_{clean_type}_{date.replace('-', '')}"
        entities.append({
            "id": entity_id[:120],
            "doc_type": "sec",
            "badge_label": f"SEC {filing_type}",
            "ticker": clean_ticker,
            "user_id": "global",
            "title": f"{clean_ticker} Form {filing_type} ({date})",
            "content": text,
            "source_url": url
        })

    vectors = embed_texts(texts_to_embed)
    for i, vec in enumerate(vectors):
        entities[i]["vector"] = vec

    try:
        res = client.upsert(collection_name=COLLECTION_NAME, data=entities)
        logger.info("✅ Synced %d SEC filings to Zilliz Cloud for ticker %s", len(entities), clean_ticker)
        return len(entities)
    except Exception as e:
        logger.error("Failed to upsert SEC filings to Milvus: %s", str(e))
        return 0


def sync_news_to_milvus(articles: List[Dict[str, Any]]) -> int:
    """
    Upserts financial news articles into Zilliz Cloud.
    """
    client = get_milvus_client()
    if client is None or not articles:
        return 0

    entities = []
    texts_to_embed = []

    for art in articles:
        ticker = str(art.get("ticker", "MARKET")).strip().upper()
        title = art.get("title", "")
        summary = art.get("summary", art.get("snippet", art.get("content", "")))
        source = art.get("source", art.get("publisher", "Live RSS"))
        url = art.get("url", art.get("link", ""))

        if not title:
            continue

        text = f"Financial Market News for {ticker} ({source}): {title}. Summary: {summary}"
        texts_to_embed.append(text)

        url_hash = hashlib.md5((url or title).encode("utf-8")).hexdigest()[:16]
        entity_id = f"news_{ticker.lower()}_{url_hash}"

        entities.append({
            "id": entity_id,
            "doc_type": "news",
            "badge_label": f"{source} (RSS)",
            "ticker": ticker,
            "user_id": "global",
            "title": title,
            "content": summary or title,
            "source_url": url
        })

    if not entities:
        return 0

    vectors = embed_texts(texts_to_embed)
    for i, vec in enumerate(vectors):
        entities[i]["vector"] = vec

    try:
        client.upsert(collection_name=COLLECTION_NAME, data=entities)
        logger.info("✅ Synced %d news articles to Zilliz Cloud", len(entities))
        return len(entities)
    except Exception as e:
        logger.error("Failed to upsert news articles to Milvus: %s", str(e))
        return 0


def search_knowledge_hybrid(
    query_text: str,
    ticker: Optional[str] = None,
    user_id: Optional[str] = None,
    limit: int = 6
) -> List[Dict[str, Any]]:
    """
    Hybrid semantic search in Zilliz Cloud combining dense vector embeddings
    with metadata filtering across SEC Filings, Portfolio Holdings, and News.
    """
    client = get_milvus_client()
    if client is None or not query_text:
        return []

    # Generate query vector
    query_vectors = embed_texts([query_text])
    query_vector = query_vectors[0]

    # Build filter expression
    filter_expr = []
    if ticker:
        clean = ticker.strip().upper()
        filter_expr.append(f"ticker == '{clean}'")
    if user_id:
        filter_expr.append(f"(user_id == '{user_id}' or user_id == 'global')")

    expr_str = " and ".join(filter_expr) if filter_expr else None

    try:
        results = client.search(
            collection_name=COLLECTION_NAME,
            data=[query_vector],
            filter=expr_str,
            limit=limit,
            output_fields=["id", "doc_type", "badge_label", "ticker", "title", "content", "source_url"]
        )
        hits = []
        if results and len(results) > 0:
            for hit in results[0]:
                entity = hit.get("entity", {})
                score = hit.get("distance", 0.0)
                # Map badge label fallback if not present
                doc_type = entity.get("doc_type", "general")
                badge = entity.get("badge_label")
                if not badge:
                    if doc_type == "sec":
                        badge = "SEC Filing"
                    elif doc_type == "portfolio":
                        badge = "Portofolio & P/L"
                    else:
                        badge = "Berita RSS"

                hits.append({
                    "id": entity.get("id", ""),
                    "doc_type": doc_type,
                    "badge_label": badge,
                    "ticker": entity.get("ticker", ""),
                    "title": entity.get("title", ""),
                    "content": entity.get("content", ""),
                    "source_url": entity.get("source_url", ""),
                    "score": round(score, 4)
                })
        return hits
    except Exception as e:
        logger.error("Milvus hybrid search error: %s", str(e))
        return []
