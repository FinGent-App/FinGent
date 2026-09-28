// FinGent/Agent/MCP/MCPTools.swift
//
// Official Apple FoundationModels Tool wrappers for remote MCP tools.
// These tools enable Apple FoundationModels to call MCP Server capabilities
// seamlessly alongside local on-device tools without bypassing the model.

import Foundation
import FoundationModels

// MARK: - 1. Financial Knowledge Vector RAG Tool (Zilliz Milvus)

struct MCPSearchFinancialRAGTool: Tool {
    let name = "searchFinancialKnowledgeRAG"
    let description = "Performs dense vector semantic search across news articles, market disclosures, and SEC regulatory filings (Form 10-K, 10-Q, 8-K) via the MCP Server."

    @Generable struct Arguments {
        @Guide(description: "The financial query, topic, or company disclosure to search deeply.")
        var query: String
    }

    func call(arguments: Arguments) async throws -> String {
        ToolCallTracker.shared.record(toolName: "search_financial_knowledge_rag", arguments: ["query": arguments.query])
        do {
            let result = try await MCPClient.shared.callTool(
                name: "search_financial_knowledge_rag",
                arguments: ["query": arguments.query, "limit": 5]
            )
            return result
        } catch {
            return "Failed to perform MCP RAG search: \(error.localizedDescription)"
        }
    }
}

// MARK: - 2. Macroeconomic Portfolio Risk Simulation Tool

struct MCPSimulateMacroPortfolioRiskTool: Tool {
    let name = "simulateMacroPortfolioRisk"
    let description = "Calculates estimated portfolio risk and projected return impact for macroeconomic events (e.g. Fed interest rate changes, inflation, currency devaluation, recession) against the user's holdings via the MCP Server."

    @Generable struct Arguments {
        @Guide(description: "The macroeconomic event or scenario to simulate, e.g. 'The Fed raises interest rates by 50 bps', 'High Inflation Surge', 'Global Recession'.")
        var event: String
    }

    func call(arguments: Arguments) async throws -> String {
        ToolCallTracker.shared.record(toolName: "simulate_macro_portfolio_risk", arguments: ["event": arguments.event])
        do {
            let result = try await MCPClient.shared.callTool(
                name: "simulate_macro_portfolio_risk",
                arguments: ["event": arguments.event, "user_id": "default_user"]
            )
            return result
        } catch {
            return "Failed to simulate portfolio risk via MCP: \(error.localizedDescription)"
        }
    }
}

// MARK: - 3. News Sentiment & Price Impact Tool

struct MCPAnalyzeNewsSentimentTool: Tool {
    let name = "analyzeNewsSentimentImpact"
    let description = "Analyzes sentiment score, bullish/bearish bias, and potential stock price direction impact for a financial headline or market theme via the MCP Server."

    @Generable struct Arguments {
        @Guide(description: "The news headline, topic, or market rumor to analyze.")
        var headline: String
    }

    func call(arguments: Arguments) async throws -> String {
        ToolCallTracker.shared.record(toolName: "analyze_news_sentiment_impact", arguments: ["headline": arguments.headline])
        do {
            let result = try await MCPClient.shared.callTool(
                name: "analyze_news_sentiment_impact",
                arguments: ["topic_or_headline": arguments.headline]
            )
            return result
        } catch {
            return "Failed to analyze news sentiment via MCP: \(error.localizedDescription)"
        }
    }
}

// MARK: - 4. Side-by-Side Stock Comparison Tool

struct MCPCompareStocksTool: Tool {
    let name = "compareStocksSideBySide"
    let description = "MANDATORY tool whenever comparing two or more stocks side-by-side (e.g. 'Compare BBCA and BMRI based on valuation multiples', 'compare AAPL and MSFT', 'which is better NVDA or AMD'). Compares real-time prices, P/E ratios, Forward P/E, PBV, ROE, EPS, dividend yields, and market caps side-by-side via the MCP Server."

    @Generable struct Arguments {
        @Guide(description: "Comma-separated stock tickers to compare, e.g. 'BBCA, BMRI' or 'AAPL, MSFT, NVDA'.")
        var tickers: String
    }

    func call(arguments: Arguments) async throws -> String {
        ToolCallTracker.shared.record(toolName: "compare_stocks_side_by_side", arguments: ["tickers": arguments.tickers])
        let tickerList = arguments.tickers
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
            .filter { !$0.isEmpty }

        guard tickerList.count >= 2 else {
            return "Please provide at least 2 stock tickers separated by commas for comparison (e.g. 'BBCA, BMRI')."
        }

        do {
            let result = try await MCPClient.shared.callTool(
                name: "compare_stocks_side_by_side",
                arguments: ["tickers": tickerList]
            )
            return result
        } catch {
            return "Failed to compare stocks via MCP: \(error.localizedDescription)"
        }
    }
}

// MARK: - 5. Stock Valuation Fundamentals Tool

struct MCPGetStockFundamentalsTool: Tool {
    let name = "getStockValuationFundamentals"
    let description = "Retrieves key financial valuation multiples and fundamental metrics for a stock (e.g. 'What is the P/E ratio and PBV of BBCA?', 'Check key financial fundamental ratios for TLKM'): Trailing P/E, Forward P/E, PBV, ROE, EPS, Free Cash Flow, Dividend Yield, and Market Cap via the MCP Server."

    @Generable struct Arguments {
        @Guide(description: "Stock ticker symbol or company name, e.g. 'BBCA', 'TLKM', 'AAPL'.")
        var ticker: String
    }

    func call(arguments: Arguments) async throws -> String {
        ToolCallTracker.shared.record(toolName: "get_stock_valuation_fundamentals", arguments: ["ticker": arguments.ticker])
        do {
            let result = try await MCPClient.shared.callTool(
                name: "get_stock_valuation_fundamentals",
                arguments: ["ticker_or_name": arguments.ticker]
            )
            return result
        } catch {
            return "Failed to fetch fundamentals via MCP: \(error.localizedDescription)"
        }
    }
}

