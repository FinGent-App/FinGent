// Agent/FinGentAgent.swift

import Foundation
import FoundationModels

@Observable
@MainActor
final class FinGentAgent {

    private var session: LanguageModelSession
    private(set) var isProcessing = false

    private static let systemInstructions = """
    You are FinGent, an intelligent Indonesian stock market portfolio assistant.

    Your capabilities:
    1. PORTFOLIO: Check portfolio summary, individual holdings, performance, allocation, top movers, and unrealized gains.
    2. STOCK & MARKET: Get stock quotes, performance, fundamentals, compare stocks, and find market movers on IHSG.
    3. NEWS & ANALYSIS: Get latest news, search news, find portfolio-related news, analyze news impact, and portfolio impact analysis.

    Guidelines:
    - Always use the available tools to fetch data before responding. Do not make up numbers.
    - Present data clearly with relevant emojis and formatting.
    - When analyzing, provide actionable insights based on the data.
    - If a user asks about a stock not in the database, let them know and suggest alternatives.
    - You can chain multiple tool calls to answer complex questions.
    - For comparison questions, use the compareStocks tool.
    - Currency is in Indonesian Rupiah (IDR/Rp).
    - Stock tickers are from the Indonesia Stock Exchange (IDX/BEI).
    - For news queries: Do NOT just output a numbered list of raw articles. Synthesize the headlines into a concise, spoken executive summary explaining the main event, key takeaway, and overall market sentiment so the user gets a quick digest.
    - Always respond in natural English with clear, concise sentences so Siri can read the answer aloud clearly.
    """

    private static var allTools: [any Tool] {
        [
            GetPortfolioSummaryTool(),
            GetHoldingTool(),
            GetPortfolioPerformanceTool(),
            GetPortfolioAllocationTool(),
            GetPortfolioMoversTool(),
            GetUnrealizedGainTool(),
            GetStockQuoteTool(),
            GetStockPerformanceTool(),
            GetStockFundamentalsTool(),
            CompareStocksTool(),
            GetMarketMoversTool(),
            GetLatestNewsTool(),
            SearchMarketNewsTool(),
            GetPortfolioNewsTool(),
            AnalyzeNewsImpactTool(),
            AnalyzePortfolioImpactTool()
        ]
    }

    init() {
        self.session = LanguageModelSession(
            tools: Self.allTools,
            instructions: Self.systemInstructions
        )
    }

    func ask(_ question: String) async throws -> String {
        isProcessing = true
        defer { isProcessing = false }
        let response = try await session.respond(to: question)
        return response.content
    }

    func resetSession() {
        session = LanguageModelSession(
            tools: Self.allTools,
            instructions: Self.systemInstructions
        )
    }
}
