#!/usr/bin/env python3
"""
Test script for FinGent Admin Endpoints and SSE Event Bus.
"""
import sys
import asyncio
from fastapi.testclient import TestClient
from main import app

client = TestClient(app)

def test_admin_api():
    print("Testing /api/v1/admin/analytics...")
    res = client.get("/api/v1/admin/analytics")
    assert res.status_code == 200, f"Expected 200, got {res.status_code}: {res.text}"
    data = res.json()
    print("Analytics OK:", data)

    print("\nTesting /api/v1/admin/tables...")
    res = client.get("/api/v1/admin/tables")
    assert res.status_code == 200, f"Expected 200, got {res.status_code}"
    tables = res.json().get("tables", [])
    print(f"Found {len(tables)} tables: {[t['table_name'] for t in tables]}")
    assert any(t['table_name'] == 'news_articles' for t in tables)

    print("\nTesting /api/v1/admin/feeds/status...")
    res = client.get("/api/v1/admin/feeds/status")
    assert res.status_code == 200, f"Expected 200, got {res.status_code}"
    feeds = res.json().get("feeds", [])
    print(f"Found {len(feeds)} RSS feeds. First: {feeds[0]['name']}")
    assert len(feeds) == 12, f"Expected 12 feeds, got {len(feeds)}"

    print("\nTesting POST /api/v1/admin/trace...")
    trace_payload = {
        "user_id": "test_admin",
        "prompt": "Kenapa saham BBCA turun hari ini?",
        "selected_tools": ["ConsultCloudAnalystTool"],
        "tool_arguments": {"ticker": "BBCA", "query": "Kenapa saham BBCA turun hari ini?"},
        "tool_output": "Fetched 4 news items from Kontan & Detik Finance",
        "final_answer": "Saham BBCA terkoreksi tipis 0.5% seiring aksi profit taking pasar modal...",
        "citations": [
            {"title": "Kinerja BBCA Kuartal II", "doc_type": "news", "badge_label": "Kontan (RSS)", "source_url": "https://kontan.co.id/news/bbca"}
        ],
        "market_type": "IDX",
        "model_name": "gemini-3.6-flash",
        "prompt_tokens": 650,
        "completion_tokens": 140,
        "latency_ms": 420,
        "relevance_score": 0.98,
        "status": "SUCCESS"
    }
    res = client.post("/api/v1/admin/trace", json=trace_payload)
    assert res.status_code == 200, f"Expected 200, got {res.status_code}: {res.text}"
    print("Trace record OK:", res.json())

    print("\nTesting /api/v1/admin/logs...")
    res = client.get("/api/v1/admin/logs?limit=5")
    assert res.status_code == 200
    logs = res.json().get("logs", [])
    assert len(logs) > 0, "Expected at least 1 log"
    print(f"Retrieved {len(logs)} logs. Top prompt: '{logs[0]['prompt']}'")
    print(f"Selected tools: {logs[0]['selected_tools']}")

    print("\n✅ All Admin API Endpoints Verified Successfully!")

if __name__ == "__main__":
    test_admin_api()
