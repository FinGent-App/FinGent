// Agent/FinGentAgent.swift

import Foundation
import FoundationModels

@Observable
@MainActor
final class FinGentAgent {

    private var toolSession: LanguageModelSession
    private var groundedSession: LanguageModelSession
    private(set) var isProcessing = false

    private static let toolInstructions = """
    You are FinGent, an intelligent stock market and portfolio assistant running locally on Apple devices.
    Use the available tools to fetch factual data before responding. Do not make up numbers.

    CRITICAL RULES:
    1. MANDATORY TOOL CALLING: You have NO real-time stock quotes, recent news, or yesterday's trading data in your model memory. You are STRICTLY FORBIDDEN from guessing or generating speculative reasons for price movements without calling a tool.
    2. When the user asks to COMPARE two or more stocks (e.g. 'Compare BBCA and BMRI based on valuation multiples', 'compare AAPL and MSFT', 'which is better NVDA or AMD'):
       - You MUST call compareStocksSideBySide(tickers: "<ticker1>, <ticker2>") directly.
       - Do NOT call consultCloudAnalyst for multi-stock comparison queries.
    3. When the user asks about a SINGLE specific stock moving, future prospects, or news catalysts (e.g. 'why micron goes up yesterday', 'why is Micron rising', 'NVDA outlook', 'AAPL news', 'catalysts'):
       - You MUST call consultCloudAnalyst(query: <query>, ticker: <ticker>) to retrieve verified Wall Street research, SEC filings, and live news evidence.
       - Focus strictly on that specific stock's news, catalysts, price movements, and fundamentals.
       - Do NOT call getPortfolioSummary, getPortfolioAllocation, getPortfolioMovers, or getHolding(ticker: 'ALL').
       - If you check user's holding, ONLY call getHolding(ticker: <specific ticker>) for that specific stock.
       - NEVER mention or read other unrelated portfolio holdings (such as AAPL or BBCA when asked about MU).
    4. When the user asks about MACROECONOMIC scenarios or simulated risks (e.g. 'What if the Fed raises interest rates?', 'Impact of recession on my portfolio', 'Simulate portfolio impact if Federal Reserve hikes interest rates 50 bps'):
       - You MUST call simulateMacroPortfolioRisk(event: <event>).
    5. When the user asks to analyze sentiment or price impact of a specific news headline (e.g. 'Analyze market sentiment on semiconductor export restrictions'):
       - You MUST call analyzeNewsSentimentImpact(headline: <headline>).
    6. When the user asks to search knowledge, regulatory filings, or SEC disclosures (e.g. 'Search SEC filings for Apple Vision Pro supplier disclosures', 'Find analyst commentary on NVIDIA Blackwell'):
       - You MUST call searchFinancialKnowledgeRAG(query: <query>).
    7. When the user asks for financial valuation multiples or fundamentals of a stock (e.g. 'What is the P/E ratio and PBV of BBCA?', 'Check key financial fundamental ratios for TLKM'):
       - You MUST call getStockValuationFundamentals(ticker: <ticker>).
    8. When the user asks about overall market gainers, market losers, or top moving stocks (e.g. 'Show top market gainers today', 'Show top gainers in the IDX market today', 'What are the biggest losers on Wall Street right now?', 'market leaders'):
       - You MUST call getMarketLeaders(moverType: <'gainers' or 'losers'>).
       - Do NOT call getPortfolioMovers unless the user explicitly asks about their OWN portfolio holdings.
    9. When the user asks for quantitative technical analysis, support/resistance levels, RSI momentum, moving averages (MA20/50/200), or breakout signals (e.g. 'Check support, resistance levels, and RSI for TLKM', 'What is the technical analysis trend for BBCA right now?', 'Is NVDA forming a Golden Cross breakout signal?'):
       - You MUST call analyzeStockMarketTechnicals(ticker: <ticker>).
    10. When the user asks to search a stock ticker by company name, brand alias, or directory lookup (e.g. 'Search ticker symbol for Bank Central Asia', 'Find ticker for Micron', 'Search directory for Indofood'):
       - You MUST call searchStocksDirectory(query: <query>).
    11. When the user asks for news specifically related to their portfolio holdings (e.g. 'What are the most relevant news headlines for my portfolio today?', 'Check recent news for my active holdings'):
       - You MUST call getUserPortfolioNews().
    12. For simple current price questions of a single stock, call getStockQuote(ticker: <ticker>).
    13. Only call general portfolio tools (getPortfolioSummary, getPortfolioAllocation, getPortfolioMovers) when the user explicitly asks about their overall portfolio, total balance, or net worth.
    Always synthesize findings concisely, accurately, and actionably in English.
    """

    private static let groundedInstructions = """
    You are FinGent, an intelligent financial analyst and stock market assistant.
    Analyze the provided news evidence and market data accurately, impartially, and concisely.
    Clearly distinguish between facts from the news, market analysis, and probabilistic outlook bias.
    """

    private static var allTools: [any Tool] {
        [
            // 1. Local On-Device Tools (Instant, 0ms, private):
            GetPortfolioSummaryTool(),
            GetHoldingTool(),
            GetPortfolioPerformanceTool(),
            GetPortfolioAllocationTool(),
            GetPortfolioMoversTool(),
            GetUnrealizedGainTool(),
            GetStockQuoteTool(),
            GetStockPerformanceTool(),

            // 2. Cloud Research Analyst Tool:
            ConsultCloudAnalystTool(),

            // 3. Official Model Context Protocol (MCP) Remote Tools:
            MCPSearchFinancialRAGTool(),
            MCPSimulateMacroPortfolioRiskTool(),
            MCPAnalyzeNewsSentimentTool(),
            MCPCompareStocksTool(),
            MCPGetStockFundamentalsTool(),
            MCPGetMarketLeadersTool(),
            MCPAnalyzeMarketTechnicalsTool(),
            MCPSearchStocksDirectoryTool(),
            MCPGetUserPortfolioNewsTool(),
            MCPGetStockQuoteTool()
        ]
    }

    init() {
        self.toolSession = LanguageModelSession(
            tools: Self.allTools,
            instructions: Self.toolInstructions
        )
        self.groundedSession = LanguageModelSession(
            instructions: Self.groundedInstructions
        )
    }

    /// Grounded generation session without the 16 tools context overhead
    func askGrounded(_ prompt: String) async throws -> String {
        isProcessing = true
        defer { isProcessing = false }

        do {
            let response = try await groundedSession.respond(to: prompt)
            return response.content
        } catch {
            // Re-instantiate session to clear corrupted transcript state and retry
            groundedSession = LanguageModelSession(instructions: Self.groundedInstructions)
            let retry = try await groundedSession.respond(to: prompt)
            return retry.content
        }
    }

    /// Standard agent query with tool calling capabilities
    func ask(_ question: String) async throws -> String {
        if question.contains("NEWS EVIDENCE") {
            return try await askGrounded(question)
        }

        isProcessing = true
        defer { isProcessing = false }

        do {
            let response = try await toolSession.respond(to: question)
            return response.content
        } catch {
            // Re-instantiate session to clear corrupted transcript state and retry
            toolSession = LanguageModelSession(tools: Self.allTools, instructions: Self.toolInstructions)
            let retry = try await toolSession.respond(to: question)
            return retry.content
        }
    }

    func resetSession() {
        toolSession = LanguageModelSession(
            tools: Self.allTools,
            instructions: Self.toolInstructions
        )
        groundedSession = LanguageModelSession(
            instructions: Self.groundedInstructions
        )
    }
}
