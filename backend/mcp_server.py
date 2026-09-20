"""
FinGent Model Context Protocol (MCP) Server
Standardized JSON-RPC 2.0 interface exposing equity valuation, market data,
Zilliz Cloud hybrid vector RAG, and macroeconomic portfolio risk analysis.
"""
import asyncio
import json
import logging
import sys
from typing import Any, Dict, List, Optional

from mcp.server.mcpserver import MCPServer
from mcp.server.transport_security import TransportSecuritySettings

from services.yahoo_service import (
    get_single_quote,
    get_stock_fundamentals,
    get_market_summary,
    search_stocks
)
from services.agent_tools_service import (
    get_market_movers,
    compare_stocks,
    get_latest_news,
    search_market_news,
    get_portfolio_news,
    analyze_news_impact,
    analyze_portfolio_impact,
    analyze_market_technicals_tool
)

logger = logging.getLogger("FinGent.MCPServer")

# ------------------------------------------------------------------------------
# Server Initialization
# ------------------------------------------------------------------------------

mcp_server = MCPServer(
    name="FinGent Financial Intelligence Server",
    instructions=(
        "FinGent MCP Server provides authoritative, real-time financial market tools, "
        "fundamental ratios, semantic vector search (Zilliz Milvus RAG), and "
        "portfolio macroeconomic scenario simulation."
    )
)


# ------------------------------------------------------------------------------
# MCP Tool Definitions
# ------------------------------------------------------------------------------

@mcp_server.tool()
def get_stock_quote(ticker_or_name: str) -> str:
    """
    Retrieves real-time or latest available quote (price, 24h change, day range, volume)
    for a stock ticker (e.g. 'BBCA', 'MU', 'AAPL') or company name (e.g. 'micron', 'bca').
    """
    try:
        quote = get_single_quote(ticker_or_name)
        return json.dumps(quote, indent=2, ensure_ascii=False)
    except Exception as e:
        return json.dumps({"error": f"Failed to retrieve quote for '{ticker_or_name}': {str(e)}"})


@mcp_server.tool()
def get_stock_valuation_fundamentals(ticker_or_name: str) -> str:
    """
    Retrieves key financial multiples and fundamental metrics:
    Trailing P/E, Forward P/E, PBV, ROE, EPS, Free Cash Flow, Dividend Yield, and Market Cap.
    """
    try:
        fund = get_stock_fundamentals(ticker_or_name)
        return json.dumps(fund, indent=2, ensure_ascii=False)
    except Exception as e:
        return json.dumps({"error": f"Failed to retrieve fundamentals for '{ticker_or_name}': {str(e)}"})


@mcp_server.tool()
def search_stocks_directory(query: str, limit: int = 5) -> str:
    """
    Searches stocks by company name, brand alias, or ticker symbol (e.g. 'micron', 'apple', 'bca').
    Returns full quote information for top matching stocks.
    """
    try:
        results = search_stocks(query, limit=limit)
        return json.dumps({"count": len(results), "matches": results}, indent=2, ensure_ascii=False)
    except Exception as e:
        return json.dumps({"error": f"Failed to search stocks for query '{query}': {str(e)}"})


@mcp_server.tool()
def get_market_leaders(mover_type: str = "gainers") -> str:
    """
    Retrieves top market gainers, losers, and benchmark index performance (IHSG).
    mover_type: 'gainers' or 'losers'.
    """
    try:
        movers = get_market_movers(mover_type)
        return json.dumps(movers, indent=2, ensure_ascii=False)
    except Exception as e:
        return json.dumps({"error": f"Failed to fetch market movers: {str(e)}"})


@mcp_server.tool()
def compare_stocks_side_by_side(tickers: List[str]) -> str:
    """
    Compares two or more stocks side-by-side on price, valuation ratios, returns, and fundamentals.
    """
    try:
        comparison = compare_stocks(tickers)
        return json.dumps(comparison, indent=2, ensure_ascii=False)
    except Exception as e:
        return json.dumps({"error": f"Failed to compare stocks: {str(e)}"})


@mcp_server.tool()
async def search_financial_knowledge_rag(query: str, limit: int = 5) -> str:
    """
    Performs dense vector semantic search across news articles, market disclosures,
    and SEC filings (Form 10-K, 10-Q, 8-K) stored in Zilliz Cloud Milvus.
    """
    try:
        hits = search_market_news(query=query, limit=limit)
        return json.dumps({"query": query, "count": len(hits), "results": hits}, indent=2, ensure_ascii=False)
    except Exception as e:
        return json.dumps({"error": f"RAG search failed: {str(e)}"})


@mcp_server.tool()
async def get_user_portfolio_news(user_id: str = "default_user", ticker: Optional[str] = None) -> str:
    """
    Retrieves recent financial news articles specifically related to stocks
    in the user's active portfolio holdings.
    """
    try:
        news = await get_portfolio_news(user_id=user_id, ticker=ticker)
        return json.dumps({"user_id": user_id, "count": len(news), "news": news}, indent=2, ensure_ascii=False)
    except Exception as e:
        return json.dumps({"error": f"Failed to fetch portfolio news: {str(e)}"})


@mcp_server.tool()
async def analyze_news_sentiment_impact(topic_or_headline: str) -> str:
    """
    Analyzes sentiment score, bullish/bearish bias, and potential price impact
    of news headlines or market topics.
    """
    try:
        impact = await analyze_news_impact(topic_or_headline)
        return json.dumps(impact, indent=2, ensure_ascii=False)
    except Exception as e:
        return json.dumps({"error": f"Failed to analyze news impact: {str(e)}"})


@mcp_server.tool()
async def simulate_macro_portfolio_risk(event: str, user_id: str = "default_user") -> str:
    """
    Calculates estimated risk level and projected return impact of macroeconomic events
    (e.g., Fed interest rate hikes, inflation, currency devaluation, recession)
    against the user's specific stock portfolio holdings.
    """
    try:
        risk = await analyze_portfolio_impact(user_id=user_id, event=event)
        return json.dumps(risk, indent=2, ensure_ascii=False)
    except Exception as e:
        return json.dumps({"error": f"Failed to simulate portfolio risk: {str(e)}"})


@mcp_server.tool()
def analyze_stock_market_technicals(ticker: str, timeframe: str = "3M") -> str:
    """
    Performs quantitative technical analysis and trend assessment for a stock ticker.
    Calculates moving averages (MA20, MA50, MA200), Golden Cross vs Death Cross breakout signals,
    RSI 14 momentum, and dynamic support & resistance levels from historical warehouse data.
    """
    try:
        analysis = analyze_market_technicals_tool(ticker, timeframe)
        return json.dumps(analysis, indent=2, ensure_ascii=False)
    except Exception as e:
        return json.dumps({"error": f"Failed to calculate technical analysis for '{ticker}': {str(e)}"})



# ------------------------------------------------------------------------------
# App Factory for FastAPI Integration
# ------------------------------------------------------------------------------

def get_sse_app():
    """
    Creates and returns the Starlette ASGI application for SSE (Server-Sent Events) transport.
    Configures TransportSecuritySettings with DNS rebinding protection disabled
    for seamless operation on Google Cloud Run and mobile clients.
    """
    sec_settings = TransportSecuritySettings(enable_dns_rebinding_protection=False)
    return mcp_server.sse_app(transport_security=sec_settings)


# ------------------------------------------------------------------------------
# Standalone CLI Entry Point (stdio transport)
# ------------------------------------------------------------------------------

if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, stream=sys.stderr)
    logger.info("Starting FinGent MCP Server over stdio...")
    asyncio.run(mcp_server.run_stdio_async())
