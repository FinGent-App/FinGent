// FinGent/Agent/Tools/CloudAnalystTool.swift

import Foundation
import FoundationModels

// MARK: - Citation Store for UI Synchronization

@MainActor
final class SharedCitationStore {
    static let shared = SharedCitationStore()
    private(set) var lastCitations: [NewsCitation] = []
    private(set) var lastCloudReport: String? = nil

    func setLastCitations(_ dtoArray: [StockApiClient.CloudConsultCitationDTO]) {
        self.lastCitations = dtoArray.map { dto in
            let source: NewsSourceType
            if dto.doc_type.lowercased() == "sec" {
                source = .sec
            } else if dto.doc_type.lowercased() == "portfolio" {
                source = .portfolio
            } else {
                let raw = (dto.badge_label ?? "") + " " + dto.title
                let parsed = NewsSourceType.from(rawString: raw)
                if parsed == .other && dto.doc_type.lowercased() == "web" {
                    source = .googleSearch
                } else {
                    source = parsed
                }
            }
            return NewsCitation(
                id: UUID().uuidString,
                title: dto.title,
                source: source,
                url: URL(string: dto.source_url ?? "https://www.google.com") ?? URL(string: "about:blank")!,
                publishedAt: Date(),
                badgeLabel: dto.badge_label ?? dto.doc_type.uppercased()
            )
        }
    }

    func setLastCloudReport(_ report: String) {
        self.lastCloudReport = report
    }

    func drainLastCloudReport() -> String? {
        let current = lastCloudReport
        lastCloudReport = nil
        return current
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
    let description = "In-depth research on a SINGLE stock's price movements, reasons for surging/dropping (e.g. 'why micron goes up yesterday', 'BBCA rumor akuisisi'), catalysts, SEC regulatory filings (10-K/8-K), and deep Live Google Web Search Grounding via Google Gemini 3.5. Strictly for SINGLE stock research. Do NOT use for comparing two or more stocks or viewing portfolio holdings."

    @Generable struct Arguments {
        @Guide(description: "The specific financial query, research topic, or complex question to analyze deeply.")
        var query: String

        @Guide(description: "Optional stock ticker symbol to focus the research on, e.g. 'BBCA', 'AAPL', 'NVDA', 'MU', 'GOTO'.")
        var ticker: String?
    }

    func call(arguments: Arguments) async throws -> String {
        ToolCallTracker.shared.record(toolName: "ConsultCloudAnalystTool")
        let explicitTicker = arguments.ticker ?? StockTickerExtractor().extractTickers(from: arguments.query).first
        let resolvedTicker = explicitTicker ?? ConversationContextManager.shared.activeTickerContext
        if let resolved = resolvedTicker {
            ConversationContextManager.shared.activeTickerContext = resolved
        }
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

            await MainActor.run {
                SharedCitationStore.shared.setLastCloudReport(response.analyst_report)
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
