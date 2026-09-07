// Agent/Tools/NewsAnalysisTools.swift
//
// MIGRATED TO CLOUD / BACKEND:
// The 5 analytical news & macroeconomic tools below have been completely migrated
// to the Python FastAPI backend (backend/services/agent_tools_service.py) & MCP Server:
//
// 1. GetLatestNewsTool        -> GET /api/v1/agent/news
// 2. SearchMarketNewsTool     -> GET /api/v1/agent/news/search (Zilliz Milvus Hybrid RAG)
// 3. GetPortfolioNewsTool     -> GET /api/v1/agent/portfolio-news (Supabase PostgreSQL)
// 4. AnalyzeNewsImpactTool    -> POST /api/v1/agent/news-impact
// 5. AnalyzePortfolioImpactTool -> POST /api/v1/agent/portfolio-impact
//
// Their computation, vector semantic search, and database aggregation now run
// on the Python backend, keeping the iOS app lean and saving device memory.
