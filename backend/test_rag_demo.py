#!/usr/bin/env python3
"""
Interactive RAG Milvus Tester for FinGent.
Usage: ./venv/bin/python test_rag_demo.py [optional query]
"""
import sys
from services.milvus_service import search_knowledge_hybrid

def main():
    query = "Bagaimana prospek portofolio dan risiko saham MU saya?"
    if len(sys.argv) > 1:
        query = " ".join(sys.argv[1:])

    print(f"\n=======================================================")
    print(f"🔍 TESTING RAG MILVUS (ZILLIZ CLOUD)")
    print(f"=======================================================")
    print(f"Pertanyaan / Query: \"{query}\"\n")

    hits = search_knowledge_hybrid(query_text=query, user_id="default_user", limit=5)

    if not hits:
        print("❌ Tidak ada hasil ditemukan. Pastikan data sudah di-sync ke Milvus.")
        return

    print(f"✅ Ditemukan {len(hits)} Dokumen Relevan dari Zilliz Cloud:\n")
    for i, h in enumerate(hits, 1):
        print(f"--- [Hasil #{i}] ---")
        print(f"🏷️  Tipe Dokumen : {h['doc_type'].upper()} ({h['badge_label']})")
        print(f"📈 Ticker       : {h['ticker']}")
        print(f"⭐ Similarity   : {h['score']} (Cosine Match)")
        print(f"📌 Judul        : {h['title']}")
        print(f"📝 Cuplikan Teks: {h['content'][:120]}...")
        if h['source_url']:
            print(f"🔗 URL Dokumen  : {h['source_url']}")
        print()

    print("=======================================================")
    print("💡 BAGAIMANA INI MEMBANTU AI CHAT?")
    print("Ketiga potongan di atas disatukan menjadi 'Grounding Context'")
    print("dan dikirim ke LLM bersama prompt user, sehingga AI menjawab")
    print("berdasarkan data asli portofolio & SEC, bukan halusinasi!")
    print("=======================================================\n")

if __name__ == "__main__":
    main()
