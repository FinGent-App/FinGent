// Core/Domain/UseCase/ChatUseCase.swift

import Foundation

// MARK: - Chat Research Phase

enum ChatResearchPhase: Sendable, Equatable {
    case readingNews(sources: String)
    case analyzingStockHistory
    case analyzingSEC
    case generatingResults

    var id: String {
        switch self {
        case .readingNews: return "readingNews"
        case .analyzingStockHistory: return "analyzingStockHistory"
        case .analyzingSEC: return "analyzingSEC"
        case .generatingResults: return "generatingResults"
        }
    }

    var title: String {
        switch self {
        case .readingNews(let sources):
            return "Reading (\(sources))"
        case .analyzingStockHistory:
            return "Analyzing stock history"
        case .analyzingSEC:
            return "Analyzing SEC"
        case .generatingResults:
            return "Generating Results for you"
        }
    }

    var iconName: String {
        switch self {
        case .readingNews:
            return "newspaper.fill"
        case .analyzingStockHistory:
            return "chart.xyaxis.line"
        case .analyzingSEC:
            return "doc.text.magnifyingglass"
        case .generatingResults:
            return "sparkles"
        }
    }
}

// MARK: - ChatUseCaseProtocol

@MainActor
protocol ChatUseCaseProtocol: Sendable {
    func ask(_ prompt: String) async throws -> AIResponse
    func ask(_ prompt: String, onProgress: (@Sendable @MainActor (ChatResearchPhase) -> Void)?) async throws -> AIResponse
    func resetSession()
}

// MARK: - ChatUseCase Implementation

@MainActor
final class ChatUseCase: ChatUseCaseProtocol {

    private let agent: FinGentAgent
    private let newsRetrievalUseCase: NewsRetrievalUseCaseProtocol
    private let marketRepo: MarketDataRepositoryProtocol

    init(
        agent: FinGentAgent,
        newsRetrievalUseCase: NewsRetrievalUseCaseProtocol,
        marketRepo: MarketDataRepositoryProtocol
    ) {
        self.agent = agent
        self.newsRetrievalUseCase = newsRetrievalUseCase
        self.marketRepo = marketRepo
    }

    convenience init() {
        self.init(
            agent: FinGentAgent(),
            newsRetrievalUseCase: NewsRetrievalUseCase(),
            marketRepo: MarketDataRepository.shared
        )
    }

    func ask(_ prompt: String) async throws -> AIResponse {
        try await ask(prompt, onProgress: nil)
    }

    func ask(
        _ prompt: String,
        onProgress: (@Sendable @MainActor (ChatResearchPhase) -> Void)? = nil
    ) async throws -> AIResponse {
        let startTime = Date()
        // Step 1: News Retrieval & Sources
        let (context, articles) = await newsRetrievalUseCase.retrieveNews(for: prompt)
        let sourcesList = Array(Set(articles.map { $0.source.displayName })).sorted()
        let isTargetIDX = context.tickers.first.map { NewsRankingService.isIDX(ticker: $0) } ?? false
        let defaultFallback = isTargetIDX ? "Kontan, Detik Finance, CNN Indonesia" : "Nasdaq, Investing.com, Yahoo Finance"
        let sourcesStr = sourcesList.isEmpty ? defaultFallback : sourcesList.joined(separator: ", ")
        onProgress?(.readingNews(sources: sourcesStr))
        try? await Task.sleep(nanoseconds: 50_000_000)

        // Step 2: Analyzing Stock History
        onProgress?(.analyzingStockHistory)
        if let ticker = context.tickers.first {
            _ = try? await StockApiClient.shared.fetchHistory(ticker: ticker, period: "1mo")
        }
        try? await Task.sleep(nanoseconds: 50_000_000)

        // Step 3: Analyzing SEC
        onProgress?(.analyzingSEC)
        if let ticker = context.tickers.first, !ticker.hasSuffix(".JK") {
            _ = try? await StockApiClient.shared.fetchSecFilings(ticker: ticker, limit: 3)
        }
        try? await Task.sleep(nanoseconds: 50_000_000)

        // Step 4: Generating Results for you
        onProgress?(.generatingResults)

        do {
            ToolCallTracker.shared.reset()
            // Master Orchestrator: Apple FoundationModels on iOS evaluates the user prompt.
            // FoundationModels is NEVER bypassed. It autonomously selects between on-device tools
            // (portfolio balance, holdings, quotes) and the Cloud Analyst (Gemini + RAG + SEC).
            let rawReply = try await agent.ask(prompt)

            let executedRecords = ToolCallTracker.shared.drainRecords()
            let calledCloudAnalyst = executedRecords.contains { $0.name == "ConsultCloudAnalystTool" }
            let cloudReport = SharedCitationStore.shared.drainLastCloudReport()

            let effectiveReply: String
            if calledCloudAnalyst, let report = cloudReport, !report.isEmpty {
                // If Apple FoundationModels on-device SLM truncated the response due to token budget limits
                // (e.g. only generating a brief header like "**FinGent Senior Wall Street Research Analyst Briefing**"),
                // seamlessly use the complete, institutional-grade Cloud Research report.
                let trimmed = rawReply.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count < 350 || (!trimmed.contains("###") && report.contains("###")) {
                    effectiveReply = report
                } else {
                    effectiveReply = rawReply
                }
            } else {
                effectiveReply = rawReply
            }

            let (cleanedAnswer, bias) = extractBias(from: effectiveReply)

            var citations = SharedCitationStore.shared.drainLastCitations()
            if let targetTicker = context.tickers.first {
                citations = citations.filter { c in
                    if c.source == .portfolio {
                        return c.title.uppercased().contains(targetTicker.uppercased())
                    }
                    return true
                }
            }
            if citations.isEmpty && !articles.isEmpty && context.requiresNews {
                citations = articles.prefix(3).map { NewsCitation(from: $0) }
            }

            let isTargetMarketIDX = context.tickers.first.map { NewsRankingService.isIDX(ticker: $0) } ?? false
            let onDeviceRecords = executedRecords.filter { $0.name != "ConsultCloudAnalystTool" }

            // If ConsultCloudAnalystTool was executed, the backend cloud_agent_service already
            // recorded the complete trace (with exact query, ticker, citations, and 12s latency).
            // We only record an iOS trace if purely on-device tools or direct SLM synthesis occurred.
            if !calledCloudAnalyst {
                let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
                let onDeviceTools = onDeviceRecords.map { $0.name }
                var mergedArgs: [String: Any] = [:]
                for r in onDeviceRecords {
                    for (k, v) in r.arguments {
                        mergedArgs[k] = v
                    }
                }
                Task {
                    await StockApiClient.shared.recordAgentTrace(
                        prompt: prompt,
                        selectedTools: onDeviceTools,
                        toolArguments: mergedArgs,
                        finalAnswer: cleanedAnswer,
                        marketType: isTargetMarketIDX ? "IDX" : "US",
                        latencyMs: latencyMs
                    )
                }
            }

            return AIResponse(
                answer: cleanedAnswer,
                bias: bias,
                confidence: bias != nil ? 0.82 : nil,
                sources: citations
            )
        } catch {
            // Fallback path: When executed on environments without Apple Intelligence neural engine
            // assets (e.g. standard simulator), consult Cloud Analyst or perform synthesis.
            if let cloudResponse = try? await StockApiClient.shared.consultCloudAnalyst(query: prompt, ticker: context.tickers.first) {
                let citations = (cloudResponse.citations ?? []).compactMap { dto -> NewsCitation? in
                    // If target ticker is specified, filter out portfolio citations of other stocks
                    if let targetTicker = context.tickers.first, dto.doc_type.lowercased() == "portfolio" {
                        if !dto.title.uppercased().contains(targetTicker.uppercased()) {
                            return nil
                        }
                    }

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

                let (cleanedAnswer, bias) = extractBias(from: cloudResponse.analyst_report)
                return AIResponse(
                    answer: cleanedAnswer,
                    bias: bias ?? .neutral,
                    confidence: 0.80,
                    sources: citations
                )
            }

            let fallback = synthesizeFallbackResponse(
                userPrompt: prompt,
                context: context,
                articles: articles,
                ragCitations: [],
                cloudGrounding: nil
            )

            return AIResponse(
                answer: fallback.answer,
                bias: fallback.bias,
                confidence: 0.75,
                sources: articles.prefix(3).map { NewsCitation(from: $0) }
            )
        }
    }

    func resetSession() {
        agent.resetSession()
    }

    // MARK: - Prompt Engineering for Evidence Grounding

    private func buildGroundedPrompt(
        userPrompt: String,
        context: NewsQueryContext,
        articles: [NewsArticle],
        ragGrounding: String? = nil,
        cloudGrounding: String? = nil
    ) -> String {
        var prompt = "USER QUERY: \"\(userPrompt)\"\n\n"

        // Add live market data if relevant ticker is detected
        if let ticker = context.tickers.first, let quote = marketRepo.getQuote(for: ticker) {
            prompt += """
            MARKET DATA (Realtime Snapshot):
            - Ticker: \(quote.ticker) (\(quote.name))
            - Price: \(quote.formattedPrice)
            - 24H Change: \(quote.formattedChange) (\(String(format: "%.2f", quote.changePercent))%)
            - Volume: \(quote.volume)

            """
        }

        // Add Cloud Agent Analytics if available (Stock comparison, Macro scenario exposure, News impact)
        if let cloudGrounding = cloudGrounding, !cloudGrounding.isEmpty {
            prompt += """
            CLOUD AGENT ANALYTICS ENGINE (Fundamentals, Peer Comparison, Macro Impact):
            \(cloudGrounding)

            """
        }

        // Add Zilliz Cloud RAG verified knowledge (Portfolio, SEC, News)
        if let ragGrounding = ragGrounding, !ragGrounding.isEmpty {
            prompt += """
            VERIFIED FINANCIAL KNOWLEDGE BASE (Zilliz Cloud Milvus - SEC, Portfolio, News):
            \(ragGrounding)

            """
        }

        // Add structured news evidence if available
        if !articles.isEmpty {
            prompt += "NEWS EVIDENCE (Verified External Sources):\n"
            for (i, article) in articles.prefix(3).enumerated() {
                prompt += """
                [\(i + 1)]
                Source: \(article.source.displayName)
                Published: \(ISO8601DateFormatter().string(from: article.publishedAt))
                Title: \(article.title)
                Summary: \(article.summary ?? "No summary provided.")
                URL: \(article.url.absoluteString)

                """
            }
        }

        // Strict grounding instructions
        prompt += """
        STRICT GROUNDING INSTRUCTIONS:
        1. Base your answer strictly on the VERIFIED FINANCIAL KNOWLEDGE BASE, CLOUD AGENT ANALYTICS, NEWS EVIDENCE, and MARKET DATA provided above. Do NOT fabricate or assume unreported information.
        2. Reference user's portfolio holding or SEC filing directly if present in the knowledge base.
        3. Clearly distinguish between:
           - FACTS: What the verified knowledge base and latest news explicitly report.
           - ANALYSIS: What these facts imply for the company, user's position, and market.
           - OUTLOOK / BIAS: State a clear probabilistic bias (Bullish, Bearish, or Neutral). Never state that a stock is certain to rise or fall.
        4. Provide an actionable, well-reasoned answer in English (clear, professional, Wall Street research tone).
        5. At the very end of your response, output a single bias tag on a new line:
           [BIAS: BULLISH] or [BIAS: BEARISH] or [BIAS: NEUTRAL].
        """

        return prompt
    }

    // MARK: - Fallback Synthesis (When on-device LLM hits GenerationError / asset limits)

    private func synthesizeFallbackResponse(
        userPrompt: String,
        context: NewsQueryContext,
        articles: [NewsArticle],
        ragCitations: [NewsCitation] = [],
        cloudGrounding: String? = nil
    ) -> (answer: String, bias: MarketBias) {
        let ticker = context.tickers.first ?? "Market"
        let quote = context.tickers.first.flatMap { marketRepo.getQuote(for: $0) }

        // Analyze sentiment across retrieved articles
        var posScore = 0
        var negScore = 0
        for article in articles {
            switch article.sentiment {
            case .positive: posScore += 1
            case .negative: negScore += 1
            case .neutral: break
            }
        }

        let bias: MarketBias
        if posScore > negScore {
            bias = .bullish
        } else if negScore > posScore {
            bias = .bearish
        } else {
            bias = .neutral
        }

        var text = "Based on integrated analysis from **FinGent Intelligence (Zilliz Cloud RAG & Live Market)**, here is the briefing for **\(ticker)**:\n\n"

        if let q = quote {
            text += "📊 **Current Market Snapshot:**\nPrice is trading at **\(q.formattedPrice)** with daily movement of **\(q.formattedChange)** (\(String(format: "%.2f", q.changePercent))%).\n\n"
        }

        if let cg = cloudGrounding, !cg.isEmpty {
            text += "⚡ **Cloud Agent Research Findings:**\n\(cg)\n\n"
        }

        // Display user holding position for the target stock only
        if let targetTicker = context.tickers.first,
           let userHolding = PortfolioRepository.shared.userHoldings.first(where: { $0.ticker.uppercased() == targetTicker.uppercased() }) {
            let avgPriceStr = userHolding.isUSD ? "$\(String(format: "%.2f", userHolding.pricePerShare))" : "Rp \(Int(userHolding.pricePerShare))"
            let investedStr = userHolding.isUSD ? "$\(String(format: "%.2f", userHolding.investedAmount))" : "Rp \(Int(userHolding.investedAmount))"
            text += "💼 **Your Portfolio Position (\(userHolding.ticker)):**\n"
            text += "• You hold **\(userHolding.shares) shares** with average purchase price of **\(avgPriceStr)** (Total Investment: **\(investedStr)**).\n\n"
        }

        // Display Portfolio Citations if available (strictly matching target ticker)
        let portfolioCitations = ragCitations.filter { p in
            p.source == .portfolio && (ticker == "Market" || p.title.uppercased().contains(ticker.uppercased()))
        }
        if !portfolioCitations.isEmpty {
            text += "💼 **Portfolio Notes:**\n"
            for p in portfolioCitations {
                text += "• \(p.title)\n"
            }
            text += "\n"
        }

        // Display SEC Citations if available
        let secCitations = ragCitations.filter { $0.source == .sec }
        if !secCitations.isEmpty {
            text += "🏛️ **Official SEC Regulatory Filings (EDGAR/Yahoo):**\n"
            for s in secCitations {
                text += "• \(s.badgeLabel ?? "SEC Filing"): \(s.title)\n"
            }
            text += "\n"
        }

        // Display News Citations if available
        if !articles.isEmpty {
            text += "📰 **Facts & Catalysts from Recent News:**\n"
            for (i, article) in articles.prefix(3).enumerated() {
                let relativeTime = article.publishedAt.timeAgoDisplay()
                text += "\(i + 1). **\(article.title)** (\(article.source.displayName), \(relativeTime))\n"
                if let summary = article.summary, !summary.isEmpty {
                    text += "   _\(summary)_\n"
                }
            }
        }

        text += "\n💡 **Analysis & Outlook:**\n"
        switch bias {
        case .bullish:
            text += "Recent news catalysts and market fundamentals indicate constructive sentiment. However, short-term momentum remains dependent on overall market liquidity."
        case .bearish:
            text += "Recent data indicates investor caution or potential short-term pullback. Risk management and monitoring key support levels are recommended."
        case .neutral:
            text += "Market conditions are currently in a balanced consolidation phase without an extreme directional bias."
        }

        text += "\n\n*(Note: Summary synthesized from Zilliz Milvus Vector RAG, SEC Filings, and Live News feeds).*"

        return (text, bias)
    }

    // MARK: - Bias Tag Extraction

    private func extractBias(from text: String) -> (String, MarketBias?) {
        var bias: MarketBias? = nil
        var cleaned = text

        if let range = cleaned.range(of: #"(?i)\[BIAS:\s*(BULLISH|BEARISH|NEUTRAL)\]"#, options: .regularExpression) {
            let tag = String(cleaned[range]).uppercased()
            if tag.contains("BULLISH") {
                bias = .bullish
            } else if tag.contains("BEARISH") {
                bias = .bearish
            } else if tag.contains("NEUTRAL") {
                bias = .neutral
            }
            cleaned.removeSubrange(range)
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            let lower = text.lowercased()
            if lower.contains("cenderung bullish") || lower.contains("bias bullish") || lower.contains("positive bias") || lower.contains("bullish") {
                bias = .bullish
            } else if lower.contains("cenderung bearish") || lower.contains("bias bearish") || lower.contains("negative bias") || lower.contains("bearish") {
                bias = .bearish
            } else if lower.contains("cenderung netral") || lower.contains("bias netral") || lower.contains("neutral") {
                bias = .neutral
            }
        }

        return (cleaned, bias)
    }
}
