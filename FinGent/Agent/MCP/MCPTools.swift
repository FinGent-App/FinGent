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

// MARK: - 6. Market Movers & Leaders Tool

struct MCPGetMarketLeadersTool: Tool {
    let name = "getMarketLeaders"
    let description = "Retrieves top market gainers, market losers, and active stocks for the overall market (e.g. 'Show top market gainers today', 'Show top gainers in the IDX market today', 'What are the biggest losers on Wall Street right now?') via the MCP Server."

    @Generable struct Arguments {
        @Guide(description: "Type of market movers: 'gainers' or 'losers'. Default is 'gainers'.")
        var moverType: String?
    }

    func call(arguments: Arguments) async throws -> String {
        let type = (arguments.moverType?.lowercased().contains("loser") == true) ? "losers" : "gainers"
        ToolCallTracker.shared.record(toolName: "get_market_leaders", arguments: ["mover_type": type])
        do {
            let result = try await MCPClient.shared.callTool(
                name: "get_market_leaders",
                arguments: ["mover_type": type]
            )
            return result
        } catch {
            return "Failed to fetch market movers via MCP: \(error.localizedDescription)"
        }
    }
}

// MARK: - 7. Stock Market Technical Analysis Tool

struct MCPAnalyzeMarketTechnicalsTool: Tool {
    let name = "analyzeStockMarketTechnicals"
    let description = "MANDATORY tool to calculate quantitative technical analysis indicators for a stock (e.g. 'Check support, resistance levels, and RSI for TLKM', 'What is the technical analysis trend for BBCA right now?', 'Is NVDA forming a Golden Cross breakout signal?'). Computes MA20, MA50, MA200, Golden/Death Cross, RSI 14 momentum, and 60-day Support & Resistance levels via the MCP Server."

    @Generable struct Arguments {
        @Guide(description: "Stock ticker symbol, e.g. 'TLKM', 'BBCA', 'NVDA', 'MU'.")
        var ticker: String
        @Guide(description: "Technical analysis timeframe period (default: '3M').")
        var timeframe: String?
    }

    func call(arguments: Arguments) async throws -> String {
        ToolCallTracker.shared.record(toolName: "analyze_stock_market_technicals", arguments: ["ticker": arguments.ticker])
        do {
            let result = try await MCPClient.shared.callTool(
                name: "analyze_stock_market_technicals",
                arguments: ["ticker": arguments.ticker, "timeframe": arguments.timeframe ?? "3M"]
            )
            return result
        } catch {
            return "Failed to calculate technicals via MCP: \(error.localizedDescription)"
        }
    }
}

// MARK: - 8. Stock Directory Search Tool

struct MCPSearchStocksDirectoryTool: Tool {
    let name = "searchStocksDirectory"
    let description = "Searches stocks by company name, brand alias, or ticker symbol (e.g. 'Search ticker symbol for Bank Central Asia', 'Find ticker for Micron', 'Search directory for Indofood') via the MCP Server."

    @Generable struct Arguments {
        @Guide(description: "Company name, brand keyword, or ticker query to search, e.g. 'Bank Central Asia', 'Micron', 'Indofood'.")
        var query: String
        @Guide(description: "Maximum number of search results to return (default: 5).")
        var limit: Int?
    }

    func call(arguments: Arguments) async throws -> String {
        let maxLimit = arguments.limit ?? 5
        ToolCallTracker.shared.record(toolName: "search_stocks_directory", arguments: ["query": arguments.query, "limit": "\(maxLimit)"])
        do {
            let result = try await MCPClient.shared.callTool(
                name: "search_stocks_directory",
                arguments: ["query": arguments.query, "limit": maxLimit]
            )
            return result
        } catch {
            return "Failed to search stocks directory via MCP: \(error.localizedDescription)"
        }
    }
}

// MARK: - 9. User Portfolio News Tool

struct MCPGetUserPortfolioNewsTool: Tool {
    let name = "getUserPortfolioNews"
    let description = "Retrieves recent financial news articles specifically related to stocks in the user's active portfolio holdings (e.g. 'What are the most relevant news headlines for my portfolio today?', 'Check recent news for my active holdings') via the MCP Server."

    @Generable struct Arguments {
        @Guide(description: "Optional specific ticker to filter portfolio news for, e.g. 'BBCA'. Leave empty for all portfolio holdings.")
        var ticker: String?
    }

    func call(arguments: Arguments) async throws -> String {
        var args: [String: Any] = ["user_id": "default_user"]
        if let ticker = arguments.ticker, !ticker.isEmpty {
            args["ticker"] = ticker
        }
        ToolCallTracker.shared.record(toolName: "get_user_portfolio_news", arguments: ["user_id": "default_user", "ticker": arguments.ticker ?? "ALL"])
        do {
            let result = try await MCPClient.shared.callTool(
                name: "get_user_portfolio_news",
                arguments: args
            )
            return result
        } catch {
            return "Failed to fetch portfolio news via MCP: \(error.localizedDescription)"
        }
    }
}

// MARK: - 10. Remote Stock Quote Tool (MCP Server Fallback)

struct MCPGetStockQuoteTool: Tool {
    let name = "getStockQuoteRemoteMCP"
    let description = "Retrieves real-time or latest available quote (price, 24h change, day range, volume) for a stock ticker (e.g. 'BBCA', 'MU', 'AAPL') or company name via the MCP Server."

    @Generable struct Arguments {
        @Guide(description: "Stock ticker symbol or company name, e.g. 'BBCA', 'MU', 'AAPL'.")
        var tickerOrName: String
    }

    func call(arguments: Arguments) async throws -> String {
        ToolCallTracker.shared.record(toolName: "get_stock_quote", arguments: ["ticker_or_name": arguments.tickerOrName])
        do {
            let result = try await MCPClient.shared.callTool(
                name: "get_stock_quote",
                arguments: ["ticker_or_name": arguments.tickerOrName]
            )
            return result
        } catch {
            return "Failed to fetch stock quote via MCP: \(error.localizedDescription)"
        }
    }
}
