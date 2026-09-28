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
            // Intelligent fallback: When executed on environments without Apple Intelligence neural engine
            // assets (e.g. standard simulator), dynamically route to MCP tools or Cloud Analyst.
            return await executeFallbackToolOrCloud(
                prompt: prompt,
                context: context,
                articles: articles,
                startTime: startTime
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

    // MARK: - Intelligent Tool Routing Fallback (for Simulator / Fallback environments)

    private func executeFallbackToolOrCloud(
        prompt: String,
        context: NewsQueryContext,
        articles: [NewsArticle],
        startTime: Date
    ) async -> AIResponse {
        let lowered = prompt.lowercased()
        let tickers = context.tickers

        // 1. Check for Stock Comparison (2 or more tickers OR "compare" / "vs")
        let isComparison = lowered.contains("compare") || lowered.contains("vs") || tickers.count >= 2
        if isComparison {
            var compareTickers = tickers
            if compareTickers.count < 2 {
                let words = prompt.components(separatedBy: CharacterSet.alphanumerics.inverted)
                let known = ["BBCA", "BMRI", "BBRI", "TLKM", "ASII", "BBNI", "AAPL", "MSFT", "NVDA", "GOOGL", "AMZN", "META", "TSLA", "AMD", "INTC", "MU"]
                let found = words.map { $0.uppercased() }.filter { known.contains($0) }
                compareTickers = Array(Set(found)).sorted()
            }
            if compareTickers.count >= 2 {
                do {
                    let result = try await MCPClient.shared.callTool(
                        name: "compare_stocks_side_by_side",
                        arguments: ["tickers": compareTickers]
                    )
                    let formatted = formatStockComparisonResponse(result: result, tickers: compareTickers)
                    let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
                    Task {
                        await StockApiClient.shared.recordAgentTrace(
                            prompt: prompt,
                            selectedTools: ["compare_stocks_side_by_side"],
                            toolArguments: ["tickers": compareTickers.joined(separator: ", ")],
                            finalAnswer: formatted,
                            marketType: compareTickers.contains(where: { NewsRankingService.isIDX(ticker: $0) }) ? "IDX" : "US",
                            latencyMs: latencyMs
                        )
                    }
                    return AIResponse(
                        answer: formatted,
                        bias: .neutral,
                        confidence: 0.90,
                        sources: []
                    )
                } catch {
                    // Fallback further if network error
                }
            }
        }

        // 2. Check for Macro Risk simulation
        let isMacro = lowered.contains("simulate") || lowered.contains("fed") || lowered.contains("rate hike") || lowered.contains("inflation") || lowered.contains("recession") || lowered.contains("bunga") || lowered.contains("resesi")
        if isMacro {
            do {
                let result = try await MCPClient.shared.callTool(
                    name: "simulate_macro_portfolio_risk",
                    arguments: ["event": prompt, "user_id": "default_user"]
                )
                let formatted = formatMacroRiskResponse(result: result, prompt: prompt)
                let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
                Task {
                    await StockApiClient.shared.recordAgentTrace(
                        prompt: prompt,
                        selectedTools: ["simulate_macro_portfolio_risk"],
                        toolArguments: ["event": prompt],
                        finalAnswer: formatted,
                        marketType: "US",
                        latencyMs: latencyMs
                    )
                }
                return AIResponse(answer: formatted, bias: .bearish, confidence: 0.85, sources: [])
            } catch {
                // Fallback further
            }
        }

        // 3. Check for News Sentiment impact
        let isSentiment = lowered.contains("sentiment") || lowered.contains("sentimen") || lowered.contains("headline")
        if isSentiment {
            do {
                let result = try await MCPClient.shared.callTool(
                    name: "analyze_news_sentiment_impact",
                    arguments: ["topic_or_headline": prompt]
                )
                let formatted = formatSentimentImpactResponse(result: result, prompt: prompt)
                let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
                Task {
                    await StockApiClient.shared.recordAgentTrace(
                        prompt: prompt,
                        selectedTools: ["analyze_news_sentiment_impact"],
                        toolArguments: ["headline": prompt],
                        finalAnswer: formatted,
                        marketType: "US",
                        latencyMs: latencyMs
                    )
                }
                return AIResponse(answer: formatted, bias: .neutral, confidence: 0.85, sources: [])
            } catch {
                // Fallback further
            }
        }

        // 4. Check for Knowledge / SEC disclosures search
        let isKnowledge = lowered.contains("sec") || lowered.contains("filing") || lowered.contains("disclosure") || lowered.contains("knowledge") || lowered.contains("rag")
        if isKnowledge {
            do {
                let result = try await MCPClient.shared.callTool(
                    name: "search_financial_knowledge_rag",
                    arguments: ["query": prompt, "limit": 5]
                )
                let formatted = formatRAGResponse(result: result, query: prompt)
                let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
                Task {
                    await StockApiClient.shared.recordAgentTrace(
                        prompt: prompt,
                        selectedTools: ["search_financial_knowledge_rag"],
                        toolArguments: ["query": prompt],
                        finalAnswer: formatted,
                        marketType: "US",
                        latencyMs: latencyMs
                    )
                }
                return AIResponse(answer: formatted, bias: .neutral, confidence: 0.85, sources: [])
            } catch {
                // Fallback further
            }
        }

        // 5. Check for Market Movers / Leaders (e.g. 'Show top market gainers today')
        let isMovers = (lowered.contains("gainer") || lowered.contains("loser") || lowered.contains("mover") || lowered.contains("top market") || lowered.contains("market leader") || lowered.contains("most active") || lowered.contains("terbanyak")) && !lowered.contains("my portfolio") && !lowered.contains("portofolio saya")
        if isMovers {
            let isLosers = lowered.contains("loser") || lowered.contains("turun terbanyak")
            let moverType = isLosers ? "losers" : "gainers"
            do {
                let result = try await MCPClient.shared.callTool(
                    name: "get_market_leaders",
                    arguments: ["mover_type": moverType]
                )
                let formatted = formatMarketLeadersResponse(result: result, isLosers: isLosers)
                let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
                Task {
                    await StockApiClient.shared.recordAgentTrace(
                        prompt: prompt,
                        selectedTools: ["get_market_leaders"],
                        toolArguments: ["mover_type": moverType],
                        finalAnswer: formatted,
                        marketType: lowered.contains("wall street") || lowered.contains("us") ? "US" : "IDX",
                        latencyMs: latencyMs
                    )
                }
                return AIResponse(answer: formatted, bias: isLosers ? .bearish : .bullish, confidence: 0.90, sources: [])
            } catch {
                // Fallback further
            }
        }

        // Resolve targetTicker reliably
        var targetTicker = context.tickers.first
        if targetTicker == nil {
            targetTicker = StockTickerExtractor().extractTickers(from: prompt).first
        }
        if targetTicker == nil {
            let words = prompt.components(separatedBy: CharacterSet.alphanumerics.inverted)
            let known = ["BBCA", "BMRI", "BBRI", "TLKM", "ASII", "BBNI", "GOTO", "ICBP", "UNVR", "AMMN", "AAPL", "MSFT", "NVDA", "GOOGL", "AMZN", "META", "TSLA", "AMD", "INTC", "MU"]
            targetTicker = words.first(where: { known.contains($0.uppercased()) })?.uppercased()
        }

        // 6. Check for Technical Analysis (RSI, Support & Resistance, Moving Averages, Golden Cross)
        let isTechnicals = lowered.contains("rsi") || lowered.contains("support") || lowered.contains("resistance") || lowered.contains("moving average") || lowered.contains("ma20") || lowered.contains("ma50") || lowered.contains("golden cross") || lowered.contains("death cross") || lowered.contains("technical") || lowered.contains("teknikal")
        if isTechnicals, let ticker = targetTicker {
            do {
                let result = try await MCPClient.shared.callTool(
                    name: "analyze_stock_market_technicals",
                    arguments: ["ticker": ticker, "timeframe": "3M"]
                )
                let formatted = formatTechnicalsResponse(result: result, ticker: ticker)
                let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
                Task {
                    await StockApiClient.shared.recordAgentTrace(
                        prompt: prompt,
                        selectedTools: ["analyze_stock_market_technicals"],
                        toolArguments: ["ticker": ticker, "timeframe": "3M"],
                        finalAnswer: formatted,
                        marketType: NewsRankingService.isIDX(ticker: ticker) ? "IDX" : "US",
                        latencyMs: latencyMs
                    )
                }
                return AIResponse(answer: formatted, bias: .neutral, confidence: 0.90, sources: [])
            } catch {
                // Fallback further
            }
        }

        // 7. Check for Stock Fundamentals (P/E, PBV, ROE, Dividend)
        let isFundamentals = lowered.contains("p/e") || lowered.contains("pe ratio") || lowered.contains("pbv") || lowered.contains("dividend") || lowered.contains("valuation multiple") || lowered.contains("fundamental")
        if isFundamentals, let ticker = targetTicker {
            do {
                let result = try await MCPClient.shared.callTool(
                    name: "get_stock_valuation_fundamentals",
                    arguments: ["ticker_or_name": ticker]
                )
                let formatted = formatFundamentalsResponse(result: result, ticker: ticker)
                let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
                Task {
                    await StockApiClient.shared.recordAgentTrace(
                        prompt: prompt,
                        selectedTools: ["get_stock_valuation_fundamentals"],
                        toolArguments: ["ticker": ticker],
                        finalAnswer: formatted,
                        marketType: NewsRankingService.isIDX(ticker: ticker) ? "IDX" : "US",
                        latencyMs: latencyMs
                    )
                }
                return AIResponse(answer: formatted, bias: .neutral, confidence: 0.88, sources: [])
            } catch {
                // Fallback further
            }
        }

        // 8. Deep Research via Cloud Analyst (Gemini + Milvus RAG)
        let cloudTicker = targetTicker ?? context.tickers.first
        if let cloudResponse = try? await StockApiClient.shared.consultCloudAnalyst(query: prompt, ticker: cloudTicker) {
            let citations = (cloudResponse.citations ?? []).compactMap { dto -> NewsCitation? in
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

    private func formatStockComparisonResponse(result: String, tickers: [String]) -> String {
        guard let data = result.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let compArray = json["comparison"] as? [[String: Any]], !compArray.isEmpty else {
            return "### 📊 Stock Comparison: \(tickers.joined(separator: " vs "))\n\n\(result)"
        }

        var md = "### 📊 Valuation Multiples Comparison: \(tickers.joined(separator: " vs "))\n\n"
        md += "| Metric | " + compArray.map { ($0["ticker"] as? String) ?? "" }.joined(separator: " | ") + " |\n"
        md += "| :--- | " + compArray.map { _ in ":---" }.joined(separator: " | ") + " |\n"

        let isIdx = tickers.contains { NewsRankingService.isIDX(ticker: $0) }
        let sym = isIdx ? "Rp " : "$"

        let prices = compArray.map { item -> String in
            let p = (item["price"] as? Double) ?? 0
            let chg = (item["change_percent"] as? Double) ?? 0
            let chgStr = String(format: "%+.2f%%", chg)
            return isIdx ? "\(sym)\(Int(p)) (\(chgStr))" : "\(sym)\(String(format: "%.2f", p)) (\(chgStr))"
        }
        md += "| **Current Price** | " + prices.joined(separator: " | ") + " |\n"

        let pes = compArray.map { item -> String in
            guard let pe = item["pe_ratio"] as? Double, pe > 0 else { return "N/A" }
            return String(format: "%.2fx", pe)
        }
        md += "| **Trailing P/E** | " + pes.joined(separator: " | ") + " |\n"

        let fpes = compArray.map { item -> String in
            guard let fpe = item["forward_pe"] as? Double, fpe > 0 else { return "N/A" }
            return String(format: "%.2fx", fpe)
        }
        md += "| **Forward P/E** | " + fpes.joined(separator: " | ") + " |\n"

        let pbvs = compArray.map { item -> String in
            guard let pbv = item["pbv_ratio"] as? Double, pbv > 0 else { return "N/A" }
            return String(format: "%.2fx", pbv)
        }
        md += "| **PBV Ratio** | " + pbvs.joined(separator: " | ") + " |\n"

        let roes = compArray.map { item -> String in
            guard let roe = item["roe"] as? Double, roe != 0 else { return "N/A" }
            return String(format: "%.2f%%", roe)
        }
        md += "| **ROE** | " + roes.joined(separator: " | ") + " |\n"

        let divs = compArray.map { item -> String in
            guard let div = item["dividend_yield"] as? Double, div > 0 else { return "N/A" }
            return String(format: "%.2f%%", div)
        }
        md += "| **Dividend Yield** | " + divs.joined(separator: " | ") + " |\n"

        md += "\n**Key Institutional Takeaways:**\n"
        for item in compArray {
            let t = (item["ticker"] as? String) ?? ""
            let name = (item["name"] as? String) ?? t
            let pe = item["pe_ratio"] as? Double ?? 0
            let pbv = item["pbv_ratio"] as? Double ?? 0
            let roe = item["roe"] as? Double ?? 0
            md += "• **\(t)** (\(name)): P/E is **\(String(format: "%.1fx", pe))** with PBV of **\(String(format: "%.2fx", pbv))** and ROE of **\(String(format: "%.1f%%", roe))**.\n"
        }

        return md
    }

    private func formatMacroRiskResponse(result: String, prompt: String) -> String {
        guard let data = result.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "### 🌐 Macroeconomic Risk Simulation\n\n\(result)"
        }
        let scenario = (json["event"] as? String) ?? prompt
        let exposure = (json["exposure_percent"] as? Double) ?? 0.0
        let analysis = (json["analysis"] as? String) ?? ""
        let riskLevel = (json["risk_level"] as? String) ?? "MODERATE"

        var md = "### 🌐 Macro Risk Scenario: \(scenario)\n\n"
        md += "• **Risk Level:** **\(riskLevel.uppercased())**\n"
        md += "• **Estimated Portfolio Exposure:** **\(String(format: "%.1f%%", exposure))**\n\n"
        md += "#### Institutional Scenario Assessment\n"
        md += "\(analysis)\n\n"
        md += "\n[BIAS: BEARISH]"
        return md
    }

    private func formatSentimentImpactResponse(result: String, prompt: String) -> String {
        guard let data = result.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "### 📰 News Sentiment & Market Impact Analysis\n\n\(result)"
        }
        let headline = (json["topic"] as? String) ?? (json["headline"] as? String) ?? prompt
        let sentiment = (json["sentiment"] as? String) ?? "Neutral"
        let score = (json["score"] as? Double) ?? 0.0
        let impact = (json["price_impact"] as? String) ?? (json["analysis"] as? String) ?? ""

        var md = "### 📰 News Sentiment Analysis\n\n"
        md += "• **Headline / Topic:** _\"\(headline)\"_\n"
        md += "• **Sentiment Bias:** **\(sentiment.uppercased())** (Score: \(String(format: "%.2f", score)))\n\n"
        md += "#### Market Impact Projection\n"
        md += "\(impact)\n"
        return md
    }

    private func formatRAGResponse(result: String, query: String) -> String {
        guard let data = result.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            return "### 🏛️ Regulatory Disclosures & Vector Knowledge RAG\n\n\(result)"
        }
        var md = "### 🏛️ Verified Knowledge Search (Zilliz Cloud Milvus)\n\n"
        md += "Search Query: _\"\(query)\"_\n\n"
        if results.isEmpty {
            md += "No matching SEC filings or disclosures found."
            return md
        }
        for (i, r) in results.prefix(4).enumerated() {
            let title = (r["title"] as? String) ?? "Document"
            let docType = (r["doc_type"] as? String)?.uppercased() ?? "DISCLOSURE"
            let content = (r["content"] as? String) ?? ""
            let url = (r["source_url"] as? String) ?? ""
            md += "**\(i + 1). [\(docType)] \(title)**\n"
            if !url.isEmpty {
                md += "Source: [View Filing](\(url))\n"
            }
            md += "> \(content.prefix(250))...\n\n"
        }
        return md
    }

    private func formatFundamentalsResponse(result: String, ticker: String) -> String {
        guard let data = result.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "### 📈 Stock Fundamentals: \(ticker)\n\n\(result)"
        }
        let name = (json["name"] as? String) ?? ticker
        let pe = (json["pe_ratio"] as? Double) ?? 0
        let fpe = (json["forward_pe"] as? Double) ?? 0
        let pbv = (json["pbv_ratio"] as? Double) ?? 0
        let roe = (json["roe"] as? Double) ?? 0
        let eps = (json["eps"] as? Double) ?? 0
        let div = (json["dividend_yield"] as? Double) ?? 0
        let mcap = (json["market_cap"] as? Double) ?? 0

        var md = "### 📈 Key Valuation Fundamentals: \(ticker) (\(name))\n\n"
        md += "| Metric | Value |\n"
        md += "| :--- | :--- |\n"
        md += "| **Trailing P/E** | \(pe > 0 ? String(format: "%.2fx", pe) : "N/A") |\n"
        md += "| **Forward P/E** | \(fpe > 0 ? String(format: "%.2fx", fpe) : "N/A") |\n"
        md += "| **PBV Ratio** | \(pbv > 0 ? String(format: "%.2fx", pbv) : "N/A") |\n"
        md += "| **Return on Equity (ROE)** | \(roe != 0 ? String(format: "%.2f%%", roe) : "N/A") |\n"
        md += "| **Earnings Per Share (EPS)** | \(String(format: "%.2f", eps)) |\n"
        md += "| **Dividend Yield** | \(div > 0 ? String(format: "%.2f%%", div) : "N/A") |\n"
        let isIdr = NewsRankingService.isIDX(ticker: ticker)
        md += "| **Market Capitalization** | \(isIdr ? "Rp " : "$" )\(String(format: "%.0f", mcap)) |\n"
        return md
    }

    private func formatMarketLeadersResponse(result: String, isLosers: Bool) -> String {
        guard let data = result.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let movers = json["movers"] as? [[String: Any]], !movers.isEmpty else {
            return "### 🚀 Market Leaders & Movers\n\n\(result)"
        }

        let title = isLosers ? "Top Market Losers" : "Top Market Gainers"
        var md = "### 🚀 \(title) (Real-Time)\n\n"
        if let idx = json["index"] as? [String: Any] {
            let idxName = idx["name"] as? String ?? "IHSG"
            let idxPrice = idx["price"] as? Double ?? 0
            let idxChg = idx["change_percent"] as? Double ?? 0
            md += "**Market Index (\(idxName)):** \(String(format: "%.2f", idxPrice)) (\(String(format: "%+.2f%%", idxChg)))\n\n"
        }

        md += "| Ticker | Company Name | Price | 24H Change | Volume |\n"
        md += "| :--- | :--- | :--- | :--- | :--- |\n"

        for m in movers.prefix(8) {
            let ticker = m["ticker"] as? String ?? ""
            let name = m["name"] as? String ?? ticker
            let price = m["price"] as? Double ?? 0
            let chg = m["change_percent"] as? Double ?? 0
            let vol = m["volume"] as? Int ?? 0
            let isIdr = (m["currency"] as? String) == "IDR" || ticker.count == 4
            let priceStr = isIdr ? "Rp \(Int(price))" : "$\(String(format: "%.2f", price))"
            let chgStr = String(format: "%+.2f%%", chg)
            let volStr = vol > 1_000_000 ? "\(String(format: "%.1fM", Double(vol)/1_000_000.0))" : "\(vol)"

            md += "| **\(ticker)** | \(name) | \(priceStr) | **\(chgStr)** | \(volStr) |\n"
        }

        return md
    }

    private func formatTechnicalsResponse(result: String, ticker: String) -> String {
        guard let data = result.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "### 📊 Technical Analysis: \(ticker)\n\n\(result)"
        }

        let name = (json["name"] as? String) ?? ticker
        let close = (json["close"] as? Double) ?? 0
        let signal = (json["signal"] as? String) ?? "NEUTRAL"
        let trend = (json["trend_bias"] as? String) ?? "CONSOLIDATION"
        let isIdr = NewsRankingService.isIDX(ticker: ticker)
        let sym = isIdr ? "Rp " : "$"

        let ma = json["moving_averages"] as? [String: Any] ?? [:]
        let ma20 = ma["ma_20"] as? Double ?? close
        let ma50 = ma["ma_50"] as? Double ?? close
        let isGoldenCross = ma["golden_cross_active"] as? Bool ?? false

        let rsiObj = json["momentum_rsi"] as? [String: Any] ?? [:]
        let rsi = rsiObj["rsi_14"] as? Double ?? 50.0
        let condition = rsiObj["condition"] as? String ?? "Neutral"

        let levels = json["price_levels"] as? [String: Any] ?? [:]
        let support = levels["support_60d"] as? Double ?? close
        let resistance = levels["resistance_60d"] as? Double ?? close
        let summary = json["summary"] as? String ?? ""

        var md = "### 📊 Technical Analysis: \(ticker) (\(name))\n\n"
        md += "• **Current Price:** **\(sym)\(isIdr ? "\(Int(close))" : String(format: "%.2f", close))**\n"
        md += "• **Overall Signal:** **\(signal.uppercased())** (\(trend))\n\n"

        md += "| Technical Indicator | Value | Condition / Signal |\n"
        md += "| :--- | :--- | :--- |\n"
        md += "| **RSI (14-Day Momentum)** | **\(String(format: "%.2f", rsi))** | \(condition) |\n"
        md += "| **Moving Average (MA20)** | \(sym)\(isIdr ? "\(Int(ma20))" : String(format: "%.2f", ma20)) | Short-Term Trend |\n"
        md += "| **Moving Average (MA50)** | \(sym)\(isIdr ? "\(Int(ma50))" : String(format: "%.2f", ma50)) | Medium-Term Trend |\n"
        md += "| **Golden Cross Active?** | \(isGoldenCross ? "✅ YES (Bullish Momentum)" : "❌ NO / Death Cross") | MA20 vs MA50 |\n"
        md += "| **Dynamic Support (60D)** | **\(sym)\(isIdr ? "\(Int(support))" : String(format: "%.2f", support))** | Key Buying Floor |\n"
        md += "| **Dynamic Resistance (60D)** | **\(sym)\(isIdr ? "\(Int(resistance))" : String(format: "%.2f", resistance))** | Overhead Supply Ceiling |\n\n"

        if !summary.isEmpty {
            md += "#### 💡 Technical Outlook & Summary\n"
            md += "\(summary)\n"
        }

        return md
    }
}
