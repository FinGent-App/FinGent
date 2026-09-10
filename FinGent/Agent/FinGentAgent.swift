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

    CRITICAL FOCUS RULES FOR STOCK INQUIRIES:
    1. When the user asks about a specific stock (e.g. 'micron kenapa naik', 'prospek NVDA', 'berita AAPL'):
       - Focus strictly on that specific stock's news, catalysts, price movements, and fundamentals.
       - For questions about why a stock is rising/falling, news catalysts, or deep analysis, call consultCloudAnalyst(query: <query>, ticker: <ticker>).
       - Do NOT call getPortfolioSummary, getPortfolioAllocation, getPortfolioMovers, or getHolding(ticker: 'ALL').
       - If you check user's holding, ONLY call getHolding(ticker: <specific ticker>) for that specific stock.
       - NEVER mention or read other unrelated portfolio holdings (such as AAPL or BBCA when asked about MU).
    2. Only call general portfolio tools (getPortfolioSummary, getPortfolioAllocation, getPortfolioMovers) when the user explicitly asks about their overall portfolio, total balance, or net worth.
    Always synthesize findings concisely, accurately, and actionably in Indonesian.
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
            MCPCompareStocksTool()
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
