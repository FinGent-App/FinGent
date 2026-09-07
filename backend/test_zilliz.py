#!/usr/bin/env python3
"""
Test script to verify connection to Zilliz Cloud (Milvus).
Usage: ./venv/bin/python test_zilliz.py
"""
import os
import sys
from dotenv import load_dotenv

load_dotenv()

uri = os.getenv("MILVUS_URI", "")
token = os.getenv("MILVUS_TOKEN", "")

print(f"Connecting to Zilliz Cloud URI: {uri}")
if not uri or ("zilliz" not in uri and "localhost" not in uri):
    print("❌ MILVUS_URI is missing or not set to a valid endpoint in .env!")
    sys.exit(1)

try:
    from pymilvus import MilvusClient
    client = MilvusClient(uri=uri, token=token)
    collections = client.list_collections()
    print("✅ Successfully connected to Zilliz Cloud Milvus!")
    print(f"Existing Collections: {collections}")
except Exception as e:
    print(f"❌ Connection failed: {e}")
    sys.exit(1)
