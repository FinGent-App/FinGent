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
    You are FinGent, an intelligent Indonesian stock market portfolio assistant.
    Use the available tools to fetch data before responding. Do not make up numbers.
    Always provide actionable, concise answers.
    """

    private static let groundedInstructions = """
    You are FinGent, an intelligent financial analyst and stock market assistant.
    Analyze the provided news evidence and market data accurately, impartially, and concisely.
    Clearly distinguish between facts from the news, market analysis, and probabilistic outlook bias.
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
