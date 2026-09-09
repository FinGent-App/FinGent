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
    For local portfolio queries (summary, holdings, performance, gain/loss) and stock quotes, use the local tools.
    For deep financial research, SEC filings, fundamental valuation, or complex macroeconomic analysis, consult the Cloud Research Analyst tool (consultCloudAnalyst) or use the specialized Model Context Protocol (MCP) tools (simulateMacroPortfolioRisk, searchFinancialKnowledgeRAG, analyzeNewsSentimentImpact, compareStocksSideBySide).
    Always synthesize findings concisely, accurately, and actionably.
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
