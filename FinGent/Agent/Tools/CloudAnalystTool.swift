// FinGent/Agent/Tools/CloudAnalystTool.swift

import Foundation
import FoundationModels

// MARK: - Citation Store for UI Synchronization

@MainActor
final class SharedCitationStore {
    static let shared = SharedCitationStore()
    private(set) var lastCitations: [NewsCitation] = []

    func setLastCitations(_ dtoArray: [StockApiClient.CloudConsultCitationDTO]) {
        self.lastCitations = dtoArray.map { dto in
            let source: NewsSourceType
            if dto.doc_type.lowercased() == "sec" {
                source = .sec
            } else if dto.doc_type.lowercased() == "portfolio" {
                source = .portfolio
            } else {
                source = NewsSourceType.from(rawString: dto.title)
            }
            return NewsCitation(
                id: UUID().uuidString,
                title: dto.title,
                source: source,
                url: URL(string: dto.source_url ?? "https://www.sec.gov") ?? URL(string: "about:blank")!,
                publishedAt: Date(),
                badgeLabel: dto.doc_type.uppercased()
            )
        }
    }

    func drainLastCitations() -> [NewsCitation] {
        let current = lastCitations
        lastCitations = []
        return current
    }
}

// MARK: - ConsultCloudAnalystTool

struct ConsultCloudAnalystTool: Tool {
    let name = "consultCloudAnalyst"
    let description = "Consults the specialized FinGent Cloud Research Agent (powered by Google Gemini with Vector RAG, SEC 10-K/8-K regulatory filings, live market fundamentals, and macroeconomic scenario simulation) for deep financial analysis, valuation assessments, SEC regulatory insights, or complex market research."

    @Generable struct Arguments {
        @Guide(description: "The specific financial query, research topic, or complex question to analyze deeply.")
        var query: String

        @Guide(description: "Optional stock ticker symbol to focus the research on, e.g. 'BBCA', 'AAPL', 'NVDA', 'MU', 'GOTO'.")
        var ticker: String?
    }

    func call(arguments: Arguments) async throws -> String {
        let resolvedTicker = arguments.ticker ?? StockTickerExtractor().extractTickers(from: arguments.query).first
        do {
            let response = try await StockApiClient.shared.consultCloudAnalyst(
                query: arguments.query,
                ticker: resolvedTicker
            )

            if let citations = response.citations, !citations.isEmpty {
                let relevant = citations.filter { c in
                    if let t = resolvedTicker, c.doc_type.lowercased() == "portfolio" {
                        return c.title.uppercased().contains(t.uppercased())
                    }
                    return true
                }
                await MainActor.run {
                    SharedCitationStore.shared.setLastCitations(relevant)
                }
            }

            var formatted = "=== CLOUD RESEARCH ANALYST BRIEFING ===\n"
            formatted += response.analyst_report

            if let citations = response.citations, !citations.isEmpty {
                let relevant = citations.filter { c in
                    if let t = resolvedTicker, c.doc_type.lowercased() == "portfolio" {
                        return c.title.uppercased().contains(t.uppercased())
                    }
                    return true
                }
                if !relevant.isEmpty {
                    formatted += "\n\nREGULATORY EVIDENCE & CITATIONS:\n"
                    for (idx, item) in relevant.prefix(4).enumerated() {
                        let urlStr = item.source_url ?? "SEC Database"
                        formatted += "\(idx + 1). [\(item.doc_type.uppercased())] \(item.title) (\(urlStr))\n"
                    }
                }
            }
            return formatted
        } catch {
            return "Failed to consult Cloud Analyst: \(error.localizedDescription). Please answer using available on-device tools."
        }
    }
}
