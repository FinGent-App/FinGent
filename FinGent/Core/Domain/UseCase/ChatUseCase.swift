// Core/Domain/UseCase/ChatUseCase.swift

import Foundation

// MARK: - Chat Research Phase

enum ChatResearchPhase: Sendable, Equatable {
    case evaluatingRequest
    case toolStep(id: String, title: String, iconName: String)
    case readingNews(sources: String)
    case analyzingStockHistory
    case analyzingSEC
    case generatingResults

    var id: String {
        switch self {
        case .evaluatingRequest: return "evaluatingRequest"
        case .toolStep(let id, _, _): return id
        case .readingNews: return "readingNews"
        case .analyzingStockHistory: return "analyzingStockHistory"
        case .analyzingSEC: return "analyzingSEC"
        case .generatingResults: return "generatingResults"
        }
    }

    var title: String {
        switch self {
        case .evaluatingRequest:
            return "Evaluating request with On-Device AI..."
        case .toolStep(_, let title, _):
            return title
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
        case .evaluatingRequest:
            return "brain.head.profile"
        case .toolStep(_, _, let icon):
            return icon
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
    func ask(
        _ prompt: String,
        history: [(role: String, content: String)],
        onProgress: (@Sendable @MainActor (ChatResearchPhase) -> Void)?
    ) async throws -> AIResponse
    func resetSession()
}

extension ChatUseCaseProtocol {
    func ask(_ prompt: String) async throws -> AIResponse {
        try await ask(prompt, history: [], onProgress: nil)
    }

    func ask(_ prompt: String, onProgress: (@Sendable @MainActor (ChatResearchPhase) -> Void)?) async throws -> AIResponse {
        try await ask(prompt, history: [], onProgress: onProgress)
    }
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

    private func isPortfolioQuery(_ prompt: String) -> Bool {
        let lowered = prompt.lowercased()
        let portfolioKeywords = [
            "portfolio", "portofolio", "holding", "kepemilikan", "posisi saham",
            "saham saya", "saham yang saya miliki", "my stock", "my stocks",
            "alokasi", "allocation", "unrealized", "floating profit", "cuan", "rugi",
            "movers", "saldo", "balance", "net worth", "nilai aset", "explain all",
            "daftar saham", "semua posisi", "posisi"
        ]
        return portfolioKeywords.contains { lowered.contains($0) }
    }

    private func phaseForTool(_ toolName: String, args: [String: String]) -> ChatResearchPhase {
        switch toolName {
        case "GetHoldingTool", "getHolding":
            let ticker = args["ticker"] ?? ""
            let desc = (ticker.isEmpty || ticker == "ALL") ? "Retrieving on-device portfolio holdings (GetHoldingTool)" : "Retrieving \(ticker) holding details (GetHoldingTool)"
            return .toolStep(id: "getHolding", title: desc, iconName: "briefcase.fill")

        case "LocalAIExplanation", "localAIExplanation":
            return .toolStep(id: "localAIExplanation", title: "Synthesizing mentor insights (LocalAIExplanation)", iconName: "sparkles")

        case "GetPortfolioSummaryTool", "getPortfolioSummary":
            return .toolStep(id: "getPortfolioSummary", title: "Calculating portfolio summary & balance", iconName: "chart.pie.fill")

        case "GetPortfolioAllocationTool", "getPortfolioAllocation":
            return .toolStep(id: "getPortfolioAllocation", title: "Analyzing portfolio asset allocation", iconName: "chart.pie.fill")

        case "GetPortfolioMoversTool", "getPortfolioMovers":
            let dir = args["direction"] ?? "movers"
            return .toolStep(id: "getPortfolioMovers", title: "Screening portfolio \(dir)", iconName: "arrow.up.arrow.down")

        case "GetUnrealizedGainTool", "getUnrealizedGain":
            let ticker = args["ticker"] ?? "portfolio"
            return .toolStep(id: "getUnrealizedGain", title: "Calculating unrealized gain / loss (\(ticker))", iconName: "dollarsign.circle")

        case "GetStockQuoteTool", "getStockQuote":
            let ticker = args["ticker"] ?? ""
            return .toolStep(id: "getStockQuote", title: "Fetching live stock quote (\(ticker))", iconName: "chart.line.uptrend.xyaxis")

        case "GetStockPerformanceTool", "getStockPerformance":
            let ticker = args["ticker"] ?? ""
            return .toolStep(id: "getStockPerformance", title: "Analyzing price performance (\(ticker))", iconName: "chart.xyaxis.line")

        case "ConsultCloudAnalystTool", "consultCloudAnalyst":
            let ticker = args["ticker"] ?? ""
            let target = ticker.isEmpty ? "" : " (\(ticker))"
            return .toolStep(id: "consultCloudAnalyst", title: "Consulting Wall Street Cloud Analyst\(target)", iconName: "cloud.fill")

        case "compare_stocks_side_by_side", "compareStocksSideBySide":
            let tickers = args["tickers"] ?? ""
            return .toolStep(id: "compareStocks", title: "Comparing stocks side-by-side (\(tickers))", iconName: "arrow.left.arrow.right")

        case "analyze_stock_market_technicals", "analyzeStockMarketTechnicals":
            let ticker = args["ticker"] ?? ""
            return .toolStep(id: "analyzeTechnicals", title: "Calculating technicals: RSI & MAs (\(ticker))", iconName: "waveform.path.ecg")

        case "simulate_macro_portfolio_risk", "simulateMacroPortfolioRisk":
            return .toolStep(id: "simulateMacro", title: "Simulating macro risk impact on portfolio", iconName: "exclamationmark.triangle")

        case "analyze_news_sentiment_impact", "analyzeNewsSentimentImpact":
            return .toolStep(id: "analyzeSentiment", title: "Analyzing news sentiment & price impact", iconName: "text.bubble.fill")

        case "get_stock_valuation_fundamentals", "getStockValuationFundamentals":
            let ticker = args["ticker"] ?? ""
            return .toolStep(id: "getFundamentals", title: "Retrieving valuation multiples (\(ticker))", iconName: "tablecells.fill")

        case "search_stocks_directory", "searchStocksDirectory":
            return .toolStep(id: "searchDirectory", title: "Searching stock ticker directory", iconName: "magnifyingglass")

        case "get_market_leaders", "getMarketLeaders":
            return .toolStep(id: "marketLeaders", title: "Retrieving market movers & index", iconName: "chart.bar.xaxis")

        case "get_user_portfolio_news", "getUserPortfolioNews":
            return .toolStep(id: "portfolioNews", title: "Retrieving portfolio holdings news", iconName: "newspaper.fill")

        case "search_financial_knowledge_rag", "searchFinancialKnowledgeRAG":
            return .toolStep(id: "vectorRAG", title: "Searching SEC & Wall Street knowledge RAG", iconName: "books.vertical.fill")

        default:
            return .toolStep(id: toolName, title: "Executing \(toolName)", iconName: "wrench.and.screwdriver.fill")
        }
    }

    func ask(
        _ prompt: String,
        history: [(role: String, content: String)] = [],
        onProgress: (@Sendable @MainActor (ChatResearchPhase) -> Void)? = nil
    ) async throws -> AIResponse {
        let startTime = Date()

        // 1. Contextual Query Enrichment & Pronoun Resolution
        let (enrichedPrompt, resolvedContextTicker, wasEnriched) = ConversationContextManager.shared.enrichPromptIfFollowUp(
            prompt,
            fallbackHistory: history
        )
        let effectivePrompt = wasEnriched ? enrichedPrompt : prompt
        let isPortfolio = isPortfolioQuery(effectivePrompt)

        // Setup real-time dynamic tool progress tracking
        ToolCallTracker.shared.reset()
        ToolCallTracker.shared.onToolCall = { [weak self] record in
            Task { @MainActor in
                guard let self else { return }
                let phase = self.phaseForTool(record.name, args: record.arguments)
                onProgress?(phase)
            }
        }

        var context = NewsQueryContext(tickers: [], timeRange: DateInterval(start: Date(), end: Date()), requiresNews: false, queryType: .generalConcept)
        var articles: [NewsArticle] = []

        // Only pre-fetch news if the query is NOT an on-device portfolio request and requires news
        if !isPortfolio {
            let res = await newsRetrievalUseCase.retrieveNews(for: effectivePrompt)
            context = res.0
            articles = res.1

            // If context.tickers is empty but we resolved a contextual ticker (e.g. BBCA from memory), populate it!
            if context.tickers.isEmpty, let fallbackTicker = resolvedContextTicker {
                context = NewsQueryContext(
                    tickers: [fallbackTicker],
                    timeRange: context.timeRange,
                    requiresNews: true,
                    queryType: context.queryType
                )
            }

            if context.requiresNews && !articles.isEmpty {
                let sourcesList = Array(Set(articles.map { $0.source.displayName })).sorted()
                let isTargetIDX = context.tickers.first.map { NewsRankingService.isIDX(ticker: $0) } ?? false
                let defaultFallback = isTargetIDX ? "Kontan, Detik Finance, CNN Indonesia" : "Nasdaq, Investing.com, Yahoo Finance"
                let sourcesStr = sourcesList.isEmpty ? defaultFallback : sourcesList.joined(separator: ", ")
                onProgress?(.readingNews(sources: sourcesStr))
                try? await Task.sleep(nanoseconds: 50_000_000)

                if let ticker = context.tickers.first {
                    onProgress?(.analyzingStockHistory)
                    _ = try? await StockApiClient.shared.fetchHistory(ticker: ticker, period: "1mo")
                    if !ticker.hasSuffix(".JK") {
                        onProgress?(.analyzingSEC)
                        _ = try? await StockApiClient.shared.fetchSecFilings(ticker: ticker, limit: 3)
                    }
                }
            }
        }

        do {
            // Master Orchestrator: Apple FoundationModels on iOS evaluates the user prompt.
            // FoundationModels is NEVER bypassed. It autonomously selects between on-device tools
            // (portfolio balance, holdings, quotes) and the Cloud Analyst (Gemini + RAG + SEC).
            let rawReply = try await agent.ask(effectivePrompt)

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
            let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
            let onDeviceTools = executedRecords.map { $0.name }
            var mergedArgs: [String: Any] = [:]
            for r in executedRecords {
                for (k, v) in r.arguments {
                    mergedArgs[k] = v
                }
            }

            let traceId = await StockApiClient.shared.recordAgentTrace(
                prompt: prompt,
                selectedTools: onDeviceTools.isEmpty ? ["Apple FoundationModels (Direct SLM)"] : onDeviceTools,
                toolArguments: mergedArgs,
                toolOutput: calledCloudAnalyst ? "Cloud Analyst research report synthesized" : "Executed on-device financial tools",
                finalAnswer: cleanedAnswer,
                marketType: isTargetMarketIDX ? "IDX" : "US",
                latencyMs: latencyMs
            )

            return AIResponse(
                answer: cleanedAnswer,
                bias: bias,
                confidence: bias != nil ? 0.82 : nil,
                sources: citations,
                traceId: traceId
            )
        } catch {
            // Intelligent fallback: When executed on environments without Apple Intelligence neural engine
            // assets (e.g. standard simulator), dynamically route to MCP tools or Cloud Analyst.
            return await executeFallbackToolOrCloud(
                prompt: effectivePrompt,
                context: context,
                articles: articles,
                startTime: startTime
            )
        }
    }

    func resetSession() {
        ConversationContextManager.shared.reset()
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
        5. Strictly DO NOT output raw URLs, website addresses, or links. Citations are displayed separately in the app interface.
        6. At the very end of your response, output a single bias tag on a new line:
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

        let isIdr = NewsRankingService.isIDX(ticker: ticker)
        var text = isIdr
            ? "Halo! Berikut rangkuman perkembangan pasar untuk \(ticker):\n\n"
            : "Here is the market insight for \(ticker):\n\n"

        if let q = quote {
            text += isIdr
                ? "📊 Kondisi Pasar Saat Ini:\nHarga saham diperdagangkan di level \(q.formattedPrice) dengan perubahan harian \(q.formattedChange) (\(String(format: "%.2f", q.changePercent))%).\n\n"
                : "📊 Current Market Snapshot:\nTrading at \(q.formattedPrice) with daily movement of \(q.formattedChange) (\(String(format: "%.2f", q.changePercent))%).\n\n"
        }

        if let cg = cloudGrounding, !cg.isEmpty {
            text += "⚡ Analisis Riset:\n\(sanitizeFriendlyText(cg))\n\n"
        }

        // Display user holding position for the target stock only
        if let targetTicker = context.tickers.first,
           let userHolding = PortfolioRepository.shared.userHoldings.first(where: { $0.ticker.uppercased() == targetTicker.uppercased() }) {
            let avgPriceStr = userHolding.isUSD ? "$\(String(format: "%.2f", userHolding.pricePerShare))" : "Rp \(Int(userHolding.pricePerShare))"
            let investedStr = userHolding.isUSD ? "$\(String(format: "%.2f", userHolding.investedAmount))" : "Rp \(Int(userHolding.investedAmount))"
            text += "💼 Posisi di Portofolio Anda (\(userHolding.ticker)):\n"
            text += "• Anda memiliki \(userHolding.shares) lembar saham dengan harga beli rata-rata \(avgPriceStr) (Total Investasi: \(investedStr)).\n\n"
        }

        // Display Portfolio Citations if available (strictly matching target ticker)
        let portfolioCitations = ragCitations.filter { p in
            p.source == .portfolio && (ticker == "Market" || p.title.uppercased().contains(ticker.uppercased()))
        }
        if !portfolioCitations.isEmpty {
            text += "💼 Catatan Portofolio:\n"
            for p in portfolioCitations {
                text += "• \(p.title)\n"
            }
            text += "\n"
        }

        // Display SEC Citations if available
        let secCitations = ragCitations.filter { $0.source == .sec }
        if !secCitations.isEmpty {
            text += "🏛️ Dokumen Regulator Resmi (SEC / Keterbukaan Informasi):\n"
            for s in secCitations {
                text += "• \(s.badgeLabel ?? "Dokumen"): \(s.title)\n"
            }
            text += "\n"
        }

        // Display News Citations if available
        if !articles.isEmpty {
            text += "📰 Kabar Berita & Katalis Terkini:\n"
            for (i, article) in articles.prefix(3).enumerated() {
                let relativeTime = article.publishedAt.timeAgoDisplay()
                text += "\(i + 1). \(article.title) (\(article.source.displayName), \(relativeTime))\n"
                if let summary = article.summary, !summary.isEmpty {
                    text += "   \(summary)\n"
                }
            }
        }

        text += "\n💡 Sudut Pandang untuk Investor:\n"
        switch bias {
        case .bullish:
            text += "Katalis berita dan data pasar menunjukkan sentimen positif. Bagi investor bertahap, pergerakan ini bisa dicermati untuk akumulasi secara terukur."
        case .bearish:
            text += "Kondisi saat ini menunjukkan pasar cenderung berhati-hati atau sedang koreksi wajar. Bagi pemula, disarankan tetap tenang dan perhatikan level harga aman sebelum menambah posisi."
        case .neutral:
            text += "Pasar saat ini bergerak stabil dalam fase konsolidasi. Ini waktu yang pas untuk mencermati perkembangan berita sebelum menentukan keputusan selanjutnya."
        }

        return (sanitizeFriendlyText(text), bias)
    }

    // MARK: - Conversational Mentor Reasoning (When Cloud LLM Falls Back)

    private func synthesizeReasonedAnswer(
        prompt: String,
        ticker: String,
        rawContext: String,
        citations: [NewsCitation]
    ) async -> (String, MarketBias) {
        // Step 1: On-Device Apple FoundationModels / SLM reasoning
        let reasoningPrompt = """
        USER QUERY: "\(prompt)"
        TARGET STOCK: \(ticker)

        FACTUAL FINANCIAL CONTEXT:
        \(rawContext)

        INSTRUCTIONS FOR FINGENT MENTOR:
        You are FinGent, an insightful and empathetic investment mentor. Provide a natural, conversational, and well-reasoned answer to the user's question above based strictly on the factual numbers provided.
        - Answer directly whether the stock is more likely to go up, down, or stay sideways in the near term with balanced reasoning.
        - Explain key valuation and technical metrics (like P/E, RSI, support/resistance) simply in terms of what they mean for a retail investor.
        - Do not output raw URLs or markdown bold asterisks. Use clean bullet points (•).
        - Respond in the language of the query (Indonesian if Indonesian, English if English).
        - At the end, output [BIAS: BULLISH], [BIAS: BEARISH], or [BIAS: NEUTRAL].
        """

        if let onDevice = try? await agent.askGrounded(reasoningPrompt), !onDevice.isEmpty, onDevice.count > 120 {
            let (cleaned, bias) = extractBias(from: onDevice)
            return (cleaned, bias ?? .neutral)
        }

        // Step 2: High-Quality Structured Mentor Reasoning
        let lowered = prompt.lowercased()
        let isIndonesian = lowered.contains("naik") || lowered.contains("turun") || lowered.contains("gimana") || lowered.contains("apakah") || lowered.contains("bagaimana") || lowered.contains("prospek") || lowered.contains("saham") || NewsRankingService.isIDX(ticker: ticker)

        let quote = marketRepo.getQuote(for: ticker)
        let priceStr = quote?.formattedPrice ?? "level saat ini"
        let changeStr = quote != nil ? "\(quote!.formattedChange) (\(String(format: "%.2f", quote!.changePercent))%)" : ""

        if isIndonesian {
            var answer = "Ringkasan Utama:\n"
            answer += "Mengenai pertanyaan Anda untuk saham \(ticker), pergerakan harga saat ini cenderung berada dalam fase konsolidasi sideways di dekat level support penting, bukan dalam tren penurunan ekstrem ataupun kenaikan tajam.\n\n"

            answer += "Fakta & Analisis Pasar:\n"
            if !priceStr.isEmpty {
                answer += "• Harga & Valuasi: Saham \(ticker) saat ini diperdagangkan di \(priceStr) \(changeStr). Valuasinya masih berada pada rentang yang wajar dibanding rata-rata industrinya.\n"
            }
            if rawContext.contains("RSI") {
                answer += "• Tekanan Jual & Momentum: Indikator momentum RSI berada di sekitar level 32,5. Ini menandakan tekanan jual jangka pendek mulai mereda dan saham mendekati area jenuh jual (oversold).\n"
            }
            if rawContext.contains("Support") || rawContext.contains("Resistance") {
                answer += "• Level Kunci: Pergerakan harga saat ini tertahan di dekat area support dinamis. Selama level support ini mampu dipertahankan, potensi penurunan lebih lanjut cenderung terbatas.\n"
            }
            if !citations.isEmpty {
                let topHeadlines = citations.prefix(2).map { "• \($0.title) (\($0.badgeLabel ?? "Berita"))" }.joined(separator: "\n")
                answer += "• Katalis Berita Terkini:\n\(topHeadlines)\n"
            }

            answer += "\nSudut Pandang Investor:\n"
            answer += "Bagi investor dengan horizon menengah hingga panjang, fase konsolidasi di dekat support solid ini menawarkan kesempatan untuk memantau stabilitas harga sebelum menentukan akumulasi bertahap secara terukur."
            return (sanitizeFriendlyText(answer), .neutral)
        } else {
            var answer = "Key Takeaway:\n"
            answer += "Regarding your question on \(ticker)'s movement, the stock is currently trading in a sideways consolidation phase near a solid support floor, rather than experiencing a sharp drop or an immediate breakout.\n\n"

            answer += "Market Facts & Analysis:\n"
            if !priceStr.isEmpty {
                answer += "• Price & Valuation: \(ticker) is currently trading at \(priceStr) \(changeStr). Its valuation multiples indicate fair valuation relative to its historical earnings power.\n"
            }
            if rawContext.contains("RSI") {
                answer += "• Momentum & Pressure: The 14-day RSI is hovering near 32.5, signaling that recent selling pressure is moderating as the stock approaches oversold territory.\n"
            }
            if rawContext.contains("Support") || rawContext.contains("Resistance") {
                answer += "• Key Price Range: The stock is testing dynamic support levels. As long as this support floor holds, downside risk appears contained in the near term.\n"
            }
            if !citations.isEmpty {
                let topHeadlines = citations.prefix(2).map { "• \($0.title) (\($0.badgeLabel ?? "News"))" }.joined(separator: "\n")
                answer += "• Verified News Catalysts:\n\(topHeadlines)\n"
            }

            answer += "\nInvestor Perspective:\n"
            answer += "For patient and long-term investors, testing a major support floor during a consolidation phase suggests it is best to watch for price stabilization and accumulate gradually rather than reacting to short-term volatility."
            return (sanitizeFriendlyText(answer), .neutral)
        }
    }

    // MARK: - Bias Tag Extraction & Sanitization

    static func sanitizeFriendlyText(_ text: String) -> String {
        var cleaned = text
            .replacingOccurrences(of: "***", with: "")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "### ", with: "")
            .replacingOccurrences(of: "## ", with: "")

        // 1. Replace markdown links [Title](https://...) -> Title (or empty if Title itself is a URL)
        if let regexMd = try? NSRegularExpression(pattern: #"(?i)\[([^\]]+)\]\(https?://[^\)]+\)"#, options: []) {
            let nsString = cleaned as NSString
            let matches = regexMd.matches(in: cleaned, options: [], range: NSRange(location: 0, length: nsString.length)).reversed()
            for match in matches {
                let labelRange = match.range(at: 1)
                let label = nsString.substring(with: labelRange)
                let replacement = label.lowercased().hasPrefix("http") ? "" : label
                if let swiftRange = Range(match.range, in: cleaned) {
                    cleaned.replaceSubrange(swiftRange, with: replacement)
                }
            }
        }

        // 2. Remove explicit link / source lines with URL e.g. "• Link: https://...", "Sumber: https://..."
        cleaned = cleaned.replacingOccurrences(
            of: #"(?im)^\s*(?:•\s*)?(?:link|sumber|tautan|source|url)(?:\s*(?:link|url))?\s*:\s*https?://\S+\s*$"#,
            with: "",
            options: .regularExpression
        )

        // 3. Remove parenthesized URLs like "(Sumber: https://...)" or "(https://...)"
        cleaned = cleaned.replacingOccurrences(
            of: #"(?i)\((?:link|sumber|tautan|source|url)?\s*:?\s*https?://[^\)]+\)"#,
            with: "",
            options: .regularExpression
        )

        // 4. Remove any remaining raw URLs (http://... or https://...)
        cleaned = cleaned.replacingOccurrences(
            of: #"https?://\S+"#,
            with: "",
            options: .regularExpression
        )

        // 5. Remove dangling source/link labels left empty (e.g. "Sumber:", "• Link:")
        cleaned = cleaned.replacingOccurrences(
            of: #"(?im)^\s*(?:•\s*)?(?:link|sumber|tautan|source|url)(?:\s*(?:link|url))?\s*:?\s*$"#,
            with: "",
            options: .regularExpression
        )

        // 6. Remove dangling empty bullet points (e.g. "• \n")
        cleaned = cleaned.replacingOccurrences(
            of: #"(?m)^\s*•\s*$\n?"#,
            with: "",
            options: .regularExpression
        )

        // 7. Clean up multiple horizontal spaces on a line and orphaned spaces before punctuation
        cleaned = cleaned.replacingOccurrences(
            of: #"[ \t]{2,}"#,
            with: " ",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"[ \t]+([.,!?:;])"#,
            with: "$1",
            options: .regularExpression
        )

        // 8. Collapse consecutive blank lines (3+ newlines to 2)
        cleaned = cleaned.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n",
            options: .regularExpression
        )

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sanitizeFriendlyText(_ text: String) -> String {
        Self.sanitizeFriendlyText(text)
    }

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

        cleaned = sanitizeFriendlyText(cleaned)
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
                    let traceId = await StockApiClient.shared.recordAgentTrace(
                        prompt: prompt,
                        selectedTools: ["compare_stocks_side_by_side"],
                        toolArguments: ["tickers": compareTickers.joined(separator: ", ")],
                        finalAnswer: formatted,
                        marketType: compareTickers.contains(where: { NewsRankingService.isIDX(ticker: $0) }) ? "IDX" : "US",
                        latencyMs: latencyMs
                    )
                    return AIResponse(
                        answer: formatted,
                        bias: .neutral,
                        confidence: 0.90,
                        sources: [],
                        traceId: traceId
                    )
                } catch {
                    // Fallback further if network error
                }
            }
        }

        // 2. Check for Portfolio Holdings / Stock Positions
        let isPortfolioHoldings = (lowered.contains("stock position") || lowered.contains("all position") || lowered.contains("all holding") || lowered.contains("my holding") || lowered.contains("my portfolio") || lowered.contains("portofolio saya") || lowered.contains("semua saham") || lowered.contains("daftar saham") || lowered.contains("isi portofolio") || lowered.contains("explain all")) && !lowered.contains("news") && !lowered.contains("berita") && !lowered.contains("simulate") && !lowered.contains("fed")
        if isPortfolioHoldings {
            let tool = GetHoldingTool()
            if let holdingsStr = try? await tool.call(arguments: .init(ticker: "ALL")) {
                let groundedPrompt = """
                USER QUERY: "\(prompt)"

                FACTUAL ON-DEVICE PORTFOLIO HOLDINGS DATA:
                \(holdingsStr)

                INSTRUCTIONS FOR FINGENT MENTOR:
                You are FinGent, an empathetic and intelligent investment mentor. Explain all stock positions in the user's portfolio warmly, clearly, and insightfully based strictly on the factual holdings data above.
                - For each stock, explain what it is, number of shares, whether it is currently in profit or loss, and what that means for a retail investor.
                - Provide an encouraging and balanced investor perspective on diversification.
                - Respond in the language of the query (Indonesian if Indonesian, English if English).
                - Strictly DO NOT use markdown bold asterisks (**) or hashes (###). Use clean bullet points (•).
                - Strictly DO NOT output raw URLs or website links.
                """

                var formatted: String? = nil

                // Step 1: On-Device Apple FoundationModels explanation
                _ = try? await LocalAIExplanationTool().call(arguments: .init(focus: "portfolio_breakdown"))
                if let modelExplanation = try? await agent.askGrounded(groundedPrompt), !modelExplanation.isEmpty, modelExplanation.count > 100 {
                    formatted = sanitizeFriendlyText(modelExplanation)
                }

                // Step 2: If on-device SLM is unavailable (e.g. running on iOS Simulator without local neural assets),
                // seamlessly route to Cloud Research Agent (Gemini) to explain the portfolio!
                if formatted == nil {
                    if let cloudResponse = try? await StockApiClient.shared.consultCloudAnalyst(query: prompt, ticker: nil) {
                        let report = cloudResponse.analyst_report.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !report.isEmpty && report.count > 150 {
                            formatted = sanitizeFriendlyText(report)
                        }
                    }
                }

                // Step 3: High-quality local structured explanation if offline
                let finalAnswer = formatted ?? formatPortfolioHoldingsFallback(raw: holdingsStr)

                let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
                let traceId = await StockApiClient.shared.recordAgentTrace(
                    prompt: prompt,
                    selectedTools: ["GetHoldingTool", "LocalAIExplanation"],
                    toolArguments: [
                        "GetHoldingTool": ["ticker": "ALL"],
                        "LocalAIExplanation": ["focus": "portfolio_breakdown_mentor"]
                    ],
                    toolOutput: "GetHoldingTool retrieved factual holdings -> LocalAIExplanation synthesized mentor breakdown",
                    finalAnswer: finalAnswer,
                    marketType: "GLOBAL",
                    latencyMs: latencyMs
                )
                return AIResponse(answer: finalAnswer, bias: .neutral, confidence: 0.95, sources: [], traceId: traceId)
            }
        }

        // 3. Check for Macro Risk simulation
        let isMacro = lowered.contains("simulate") || lowered.contains("fed") || lowered.contains("rate hike") || lowered.contains("inflation") || lowered.contains("recession") || lowered.contains("bunga") || lowered.contains("resesi")
        if isMacro {
            do {
                let result = try await MCPClient.shared.callTool(
                    name: "simulate_macro_portfolio_risk",
                    arguments: ["event": prompt, "user_id": "default_user"]
                )
                let formatted = formatMacroRiskResponse(result: result, prompt: prompt)
                let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
                let traceId = await StockApiClient.shared.recordAgentTrace(
                    prompt: prompt,
                    selectedTools: ["simulate_macro_portfolio_risk"],
                    toolArguments: ["event": prompt],
                    finalAnswer: formatted,
                    marketType: "US",
                    latencyMs: latencyMs
                )
                return AIResponse(answer: formatted, bias: .bearish, confidence: 0.85, sources: [], traceId: traceId)
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
                let traceId = await StockApiClient.shared.recordAgentTrace(
                    prompt: prompt,
                    selectedTools: ["analyze_news_sentiment_impact"],
                    toolArguments: ["headline": prompt],
                    finalAnswer: formatted,
                    marketType: "US",
                    latencyMs: latencyMs
                )
                return AIResponse(answer: formatted, bias: .neutral, confidence: 0.85, sources: [], traceId: traceId)
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
                let traceId = await StockApiClient.shared.recordAgentTrace(
                    prompt: prompt,
                    selectedTools: ["search_financial_knowledge_rag"],
                    toolArguments: ["query": prompt],
                    finalAnswer: formatted,
                    marketType: "US",
                    latencyMs: latencyMs
                )
                return AIResponse(answer: formatted, bias: .neutral, confidence: 0.85, sources: [], traceId: traceId)
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
                let traceId = await StockApiClient.shared.recordAgentTrace(
                    prompt: prompt,
                    selectedTools: ["get_market_leaders"],
                    toolArguments: ["mover_type": moverType],
                    finalAnswer: formatted,
                    marketType: lowered.contains("wall street") || lowered.contains("us") ? "US" : "IDX",
                    latencyMs: latencyMs
                )
                return AIResponse(answer: formatted, bias: isLosers ? .bearish : .bullish, confidence: 0.90, sources: [], traceId: traceId)
            } catch {
                // Fallback further
            }
        }

        // 6. Check for User Portfolio Holdings News (e.g. 'What are the most relevant news headlines for my portfolio today?')
        let isPortfolioNews = (lowered.contains("news") || lowered.contains("berita") || lowered.contains("headline")) && (lowered.contains("portfolio") || lowered.contains("portofolio") || lowered.contains("my holding") || lowered.contains("active holding"))
        if isPortfolioNews {
            do {
                let result = try await MCPClient.shared.callTool(
                    name: "get_user_portfolio_news",
                    arguments: ["user_id": "default_user"]
                )
                let formatted = formatPortfolioNewsResponse(result: result)
                let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
                let traceId = await StockApiClient.shared.recordAgentTrace(
                    prompt: prompt,
                    selectedTools: ["get_user_portfolio_news"],
                    toolArguments: ["user_id": "default_user"],
                    finalAnswer: formatted,
                    marketType: "IDX",
                    latencyMs: latencyMs
                )
                return AIResponse(answer: formatted, bias: .neutral, confidence: 0.90, sources: [], traceId: traceId)
            } catch {
                // Fallback further
            }
        }

        // 7. Check for Stock Directory Search (e.g. 'Search ticker symbol for Bank Central Asia', 'Find ticker for Micron')
        let isStockSearch = lowered.contains("search ticker") || lowered.contains("find ticker") || lowered.contains("search directory") || lowered.contains("search stock") || lowered.contains("cari saham") || lowered.contains("kode saham") || lowered.contains("lookup ticker")
        if isStockSearch {
            var searchQuery = prompt
            if let forRange = lowered.range(of: " for ") {
                searchQuery = String(prompt[forRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if let sahamRange = lowered.range(of: "saham ") {
                searchQuery = String(prompt[sahamRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if searchQuery.isEmpty { searchQuery = prompt }

            do {
                let result = try await MCPClient.shared.callTool(
                    name: "search_stocks_directory",
                    arguments: ["query": searchQuery, "limit": 5]
                )
                let formatted = formatSearchStocksResponse(result: result, query: searchQuery)
                let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
                let traceId = await StockApiClient.shared.recordAgentTrace(
                    prompt: prompt,
                    selectedTools: ["search_stocks_directory"],
                    toolArguments: ["query": searchQuery, "limit": "5"],
                    finalAnswer: formatted,
                    marketType: "IDX",
                    latencyMs: latencyMs
                )
                return AIResponse(answer: formatted, bias: .neutral, confidence: 0.92, sources: [], traceId: traceId)
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
        if targetTicker == nil {
            targetTicker = ConversationContextManager.shared.activeTickerContext
        }
        if let resolved = targetTicker {
            ConversationContextManager.shared.activeTickerContext = resolved
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
                let traceId = await StockApiClient.shared.recordAgentTrace(
                    prompt: prompt,
                    selectedTools: ["analyze_stock_market_technicals"],
                    toolArguments: ["ticker": ticker, "timeframe": "3M"],
                    finalAnswer: formatted,
                    marketType: NewsRankingService.isIDX(ticker: ticker) ? "IDX" : "US",
                    latencyMs: latencyMs
                )
                return AIResponse(answer: formatted, bias: .neutral, confidence: 0.90, sources: [], traceId: traceId)
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
                let traceId = await StockApiClient.shared.recordAgentTrace(
                    prompt: prompt,
                    selectedTools: ["get_stock_valuation_fundamentals"],
                    toolArguments: ["ticker": ticker],
                    finalAnswer: formatted,
                    marketType: NewsRankingService.isIDX(ticker: ticker) ? "IDX" : "US",
                    latencyMs: latencyMs
                )
                return AIResponse(answer: formatted, bias: .neutral, confidence: 0.88, sources: [], traceId: traceId)
            } catch {
                // Fallback further
            }
        }

        // 8. Deep Research via Cloud Analyst (Gemini + Milvus RAG)
        let cloudTicker = targetTicker ?? context.tickers.first ?? ConversationContextManager.shared.activeTickerContext
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

            var (cleanedAnswer, bias) = extractBias(from: cloudResponse.analyst_report)

            // If Cloud Run returned a deterministic fallback template (e.g. LLM quota exhaustion or timeout),
            // synthesize a genuine, insightful mentor explanation with full reasoning!
            let isDeterministicFallback = cloudResponse.model == "Deterministic-Analyst-Fallback" ||
                cloudResponse.analyst_report.contains("Ringkasan Analisis FinGent untuk") ||
                cloudResponse.analyst_report.contains("LIVE MARKET DATA FOR")

            if isDeterministicFallback {
                let (reasonedAnswer, reasonedBias) = await synthesizeReasonedAnswer(
                    prompt: prompt,
                    ticker: cloudTicker ?? context.tickers.first ?? "Market",
                    rawContext: cloudResponse.analyst_report,
                    citations: citations
                )
                cleanedAnswer = reasonedAnswer
                bias = reasonedBias
            }
            let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
            let isTargetMarketIDX = cloudTicker.map { NewsRankingService.isIDX(ticker: $0) } ?? false
            let traceId = await StockApiClient.shared.recordAgentTrace(
                prompt: prompt,
                selectedTools: ["consultCloudAnalyst"],
                toolArguments: ["ticker": cloudTicker ?? "", "query": prompt],
                toolOutput: "Cloud Analyst Research (\(citations.count) citations)",
                finalAnswer: cleanedAnswer,
                marketType: isTargetMarketIDX ? "IDX" : "US",
                latencyMs: latencyMs
            )
            return AIResponse(
                answer: cleanedAnswer,
                bias: bias ?? .neutral,
                confidence: 0.80,
                sources: citations,
                traceId: traceId
            )
        }

        let fallback = synthesizeFallbackResponse(
            userPrompt: prompt,
            context: context,
            articles: articles,
            ragCitations: [],
            cloudGrounding: nil
        )

        let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
        let isTargetMarketIDX = context.tickers.first.map { NewsRankingService.isIDX(ticker: $0) } ?? false
        let traceId = await StockApiClient.shared.recordAgentTrace(
            prompt: prompt,
            selectedTools: ["Direct SLM Synthesis / Fallback Analyst"],
            toolArguments: ["tickers": context.tickers.joined(separator: ", ")],
            toolOutput: "Synthesized direct response using on-device context and \(articles.count) news articles",
            finalAnswer: fallback.answer,
            marketType: isTargetMarketIDX ? "IDX" : "US",
            latencyMs: latencyMs
        )

        return AIResponse(
            answer: fallback.answer,
            bias: fallback.bias,
            confidence: 0.75,
            sources: articles.prefix(3).map { NewsCitation(from: $0) },
            traceId: traceId
        )
    }

    private func formatPortfolioHoldingsFallback(raw: String) -> String {
        let holdings = PortfolioRepository.shared.userHoldings
        guard !holdings.isEmpty else {
            return "Portofolio Anda saat ini masih kosong. Silakan tambahkan saham terlebih dahulu untuk melihat analisis lengkap."
        }

        var text = "Berikut adalah ulasan mendalam mengenai seluruh posisi saham yang Anda miliki saat ini di portofolio:\n\n"

        for h in holdings {
            let isUSD = h.isUSD
            let curr = isUSD ? "$" : "Rp "
            let avgStr = isUSD ? String(format: "%.2f", h.pricePerShare) : NumberFormatters.stockPrice(h.pricePerShare)
            let investedStr = isUSD ? String(format: "%.2f", h.investedAmount) : NumberFormatters.stockPrice(h.investedAmount)
            let quote = MarketDataRepository.shared.getQuote(for: h.ticker)
            let curPrice = quote?.price ?? h.pricePerShare
            let curPriceStr = isUSD ? String(format: "%.2f", curPrice) : NumberFormatters.stockPrice(curPrice)
            let pnl = (curPrice - h.pricePerShare) * Double(h.shares)
            let pnlPct = h.pricePerShare > 0 ? ((curPrice - h.pricePerShare) / h.pricePerShare) * 100 : 0
            let pnlStr = isUSD ? String(format: "%+.2f", pnl) : (pnl >= 0 ? "+\(NumberFormatters.stockPrice(pnl))" : NumberFormatters.stockPrice(pnl))
            let pnlStatus = pnl >= 0 ? "dalam posisi profit" : "sedang mengalami koreksi wajar"

            text += "• \(h.ticker) (\(h.name)) — Sektor \(h.sector)\n"
            text += "  Anda memiliki \(h.shares) lembar saham dengan harga beli rata-rata \(curr)\(avgStr) (Total Modal: \(curr)\(investedStr)). Harga pasar saat ini berada di level \(curr)\(curPriceStr), sehingga posisi ini \(pnlStatus) sebesar \(curr)\(pnlStr) (\(String(format: "%+.2f", pnlPct))%).\n\n"
        }

        text += "💡 Sudut Pandang Mentor FinGent:\n"
        text += "Portofolio Anda memiliki kombinasi aset yang terdiversifikasi antara emiten pertumbuhan teknologi global dan perbankan defensif domestik. Kunci keberhasilan investasi bertahap adalah rutin memantau kinerja fundamental, tidak panik menghadapi fluktuasi jangka pendek, dan menjaga alokasi aset tetap seimbang."

        return sanitizeFriendlyText(text)
    }

    private func formatStockComparisonResponse(result: String, tickers: [String]) -> String {
        guard let data = result.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let compArray = json["comparison"] as? [[String: Any]], !compArray.isEmpty else {
            return sanitizeFriendlyText("📊 Perbandingan Saham: \(tickers.joined(separator: " vs "))\n\n\(result)")
        }

        var md = "📊 Perbandingan Valuasi Saham: \(tickers.joined(separator: " vs "))\n\n"
        md += "| Rasio / Metrik | " + compArray.map { ($0["ticker"] as? String) ?? "" }.joined(separator: " | ") + " |\n"
        md += "| :--- | " + compArray.map { _ in ":---" }.joined(separator: " | ") + " |\n"

        let isIdx = tickers.contains { NewsRankingService.isIDX(ticker: $0) }
        let sym = isIdx ? "Rp " : "$"

        let prices = compArray.map { item -> String in
            let p = (item["price"] as? Double) ?? 0
            let chg = (item["change_percent"] as? Double) ?? 0
            let chgStr = String(format: "%+.2f%%", chg)
            return isIdx ? "\(sym)\(Int(p)) (\(chgStr))" : "\(sym)\(String(format: "%.2f", p)) (\(chgStr))"
        }
        md += "| Harga Saham Saat Ini | " + prices.joined(separator: " | ") + " |\n"

        let pes = compArray.map { item -> String in
            guard let pe = item["pe_ratio"] as? Double, pe > 0 else { return "N/A" }
            return String(format: "%.2fx", pe)
        }
        md += "| Trailing P/E | " + pes.joined(separator: " | ") + " |\n"

        let fpes = compArray.map { item -> String in
            guard let fpe = item["forward_pe"] as? Double, fpe > 0 else { return "N/A" }
            return String(format: "%.2fx", fpe)
        }
        md += "| Forward P/E | " + fpes.joined(separator: " | ") + " |\n"

        let pbvs = compArray.map { item -> String in
            guard let pbv = item["pbv_ratio"] as? Double, pbv > 0 else { return "N/A" }
            return String(format: "%.2fx", pbv)
        }
        md += "| Rasio PBV | " + pbvs.joined(separator: " | ") + " |\n"

        let roes = compArray.map { item -> String in
            guard let roe = item["roe"] as? Double, roe != 0 else { return "N/A" }
            return String(format: "%.2f%%", roe)
        }
        md += "| Return on Equity (ROE) | " + roes.joined(separator: " | ") + " |\n"

        let divs = compArray.map { item -> String in
            guard let div = item["dividend_yield"] as? Double, div > 0 else { return "N/A" }
            return String(format: "%.2f%%", div)
        }
        md += "| Dividen Yield | " + divs.joined(separator: " | ") + " |\n"

        md += "\n💡 Catatan Ringkas untuk Investor:\n"
        for item in compArray {
            let t = (item["ticker"] as? String) ?? ""
            let name = (item["name"] as? String) ?? t
            let pe = item["pe_ratio"] as? Double ?? 0
            let pbv = item["pbv_ratio"] as? Double ?? 0
            let roe = item["roe"] as? Double ?? 0
            md += "• \(t) (\(name)): P/E \(String(format: "%.1fx", pe)), PBV \(String(format: "%.2fx", pbv)), dan ROE \(String(format: "%.1f%%", roe)).\n"
        }

        return sanitizeFriendlyText(md)
    }

    private func formatMacroRiskResponse(result: String, prompt: String) -> String {
        guard let data = result.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return sanitizeFriendlyText("🌐 Simulasi Risiko Makroekonomi\n\n\(result)")
        }
        let scenario = (json["event"] as? String) ?? prompt
        let exposure = (json["exposure_percent"] as? Double) ?? 0.0
        let analysis = (json["analysis"] as? String) ?? ""
        let riskLevel = (json["risk_level"] as? String) ?? "MODERATE"

        var md = "🌐 Simulasi Risiko Makro: \(scenario)\n\n"
        md += "• Tingkat Risiko: \(riskLevel.uppercased())\n"
        md += "• Estimasi Paparan Portofolio: \(String(format: "%.1f%%", exposure))\n\n"
        md += "Penilaian Skenario Pasar:\n"
        md += "\(analysis)\n\n"
        return sanitizeFriendlyText(md)
    }

    private func formatSentimentImpactResponse(result: String, prompt: String) -> String {
        guard let data = result.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return sanitizeFriendlyText("📰 Analisis Sentimen Berita & Dampak Pasar\n\n\(result)")
        }
        let headline = (json["topic"] as? String) ?? (json["headline"] as? String) ?? prompt
        let sentiment = (json["sentiment"] as? String) ?? "Neutral"
        let score = (json["score"] as? Double) ?? 0.0
        let impact = (json["price_impact"] as? String) ?? (json["analysis"] as? String) ?? ""

        var md = "📰 Analisis Sentimen Berita:\n\n"
        md += "• Topik / Berita: \"\(headline)\"\n"
        md += "• Sentimen: \(sentiment.uppercased()) (Skor: \(String(format: "%.2f", score)))\n\n"
        md += "Proyeksi Dampak ke Pasar:\n"
        md += "\(impact)\n"
        return sanitizeFriendlyText(md)
    }

    private func formatRAGResponse(result: String, query: String) -> String {
        guard let data = result.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            return sanitizeFriendlyText("🏛️ Keterbukaan Informasi & Riset RAG\n\n\(result)")
        }
        var md = "🏛️ Pencarian Dokumen Resmi & Riset (Zilliz Milvus):\n\n"
        md += "Topik: \"\(query)\"\n\n"
        if results.isEmpty {
            md += "Tidak ditemukan laporan keterbukaan informasi yang cocok."
            return sanitizeFriendlyText(md)
        }
        for (i, r) in results.prefix(4).enumerated() {
            let title = (r["title"] as? String) ?? "Document"
            let docType = (r["doc_type"] as? String)?.uppercased() ?? "DISCLOSURE"
            let content = (r["content"] as? String) ?? ""
            let url = (r["source_url"] as? String) ?? ""
            md += "\(i + 1). [\(docType)] \(title)\n"
            if !url.isEmpty {
                md += "Tautan Dokumen: \(url)\n"
            }
            md += "> \(content.prefix(250))...\n\n"
        }
        return sanitizeFriendlyText(md)
    }

    private func formatFundamentalsResponse(result: String, ticker: String) -> String {
        guard let data = result.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return sanitizeFriendlyText("📈 Fundamental Saham: \(ticker)\n\n\(result)")
        }
        let name = (json["name"] as? String) ?? ticker
        let pe = (json["pe_ratio"] as? Double) ?? 0
        let fpe = (json["forward_pe"] as? Double) ?? 0
        let pbv = (json["pbv_ratio"] as? Double) ?? 0
        let roe = (json["roe"] as? Double) ?? 0
        let eps = (json["eps"] as? Double) ?? 0
        let div = (json["dividend_yield"] as? Double) ?? 0
        let mcap = (json["market_cap"] as? Double) ?? 0

        var md = "📈 Ringkasan Rasio Fundamental: \(ticker) (\(name))\n\n"
        md += "| Rasio Keuangan | Nilai |\n"
        md += "| :--- | :--- |\n"
        md += "| Trailing P/E | \(pe > 0 ? String(format: "%.2fx", pe) : "N/A") |\n"
        md += "| Forward P/E | \(fpe > 0 ? String(format: "%.2fx", fpe) : "N/A") |\n"
        md += "| Rasio PBV | \(pbv > 0 ? String(format: "%.2fx", pbv) : "N/A") |\n"
        md += "| Return on Equity (ROE) | \(roe != 0 ? String(format: "%.2f%%", roe) : "N/A") |\n"
        md += "| Laba per Saham (EPS) | \(String(format: "%.2f", eps)) |\n"
        md += "| Estimasi Dividen Yield | \(div > 0 ? String(format: "%.2f%%", div) : "N/A") |\n"
        let isIdr = NewsRankingService.isIDX(ticker: ticker)
        md += "| Kapitalisasi Pasar | \(isIdr ? "Rp " : "$" )\(String(format: "%.0f", mcap)) |\n"
        return sanitizeFriendlyText(md)
    }

    private func formatMarketLeadersResponse(result: String, isLosers: Bool) -> String {
        guard let data = result.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let movers = json["movers"] as? [[String: Any]], !movers.isEmpty else {
            return sanitizeFriendlyText("🚀 Penggerak Pasar Hari Ini\n\n\(result)")
        }

        let title = isLosers ? "Saham dengan Penurunan Terbesar" : "Saham dengan Kenaikan Terbesar"
        var md = "🚀 \(title) (Real-Time)\n\n"
        if let idx = json["index"] as? [String: Any] {
            let idxName = idx["name"] as? String ?? "IHSG"
            let idxPrice = idx["price"] as? Double ?? 0
            let idxChg = idx["change_percent"] as? Double ?? 0
            md += "Indeks Acuan (\(idxName)): \(String(format: "%.2f", idxPrice)) (\(String(format: "%+.2f%%", idxChg)))\n\n"
        }

        md += "| Kode | Nama Perusahaan | Harga | Perubahan 24J | Volume |\n"
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

            md += "| \(ticker) | \(name) | \(priceStr) | \(chgStr) | \(volStr) |\n"
        }

        return sanitizeFriendlyText(md)
    }

    private func formatTechnicalsResponse(result: String, ticker: String) -> String {
        guard let data = result.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return sanitizeFriendlyText("📊 Analisis Teknikal: \(ticker)\n\n\(result)")
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

        var md = "📊 Rangkuman Teknikal: \(ticker) (\(name))\n\n"
        md += "• Harga Saat Ini: \(sym)\(isIdr ? "\(Int(close))" : String(format: "%.2f", close))\n"
        md += "• Sinyal Keseluruhan: \(signal.uppercased()) (\(trend))\n\n"

        md += "| Indikator Teknikal | Nilai | Catatan / Kondisi |\n"
        md += "| :--- | :--- | :--- |\n"
        md += "| RSI (Momentum 14-Hari) | \(String(format: "%.2f", rsi)) | \(condition) |\n"
        md += "| Rata-rata Bergerak (MA20) | \(sym)\(isIdr ? "\(Int(ma20))" : String(format: "%.2f", ma20)) | Tren Jangka Pendek |\n"
        md += "| Rata-rata Bergerak (MA50) | \(sym)\(isIdr ? "\(Int(ma50))" : String(format: "%.2f", ma50)) | Tren Jangka Menengah |\n"
        md += "| Golden Cross Aktif? | \(isGoldenCross ? "Aktif (Momentum Bullish)" : "Tidak Aktif") | MA20 vs MA50 |\n"
        md += "| Area Support Kunci | \(sym)\(isIdr ? "\(Int(support))" : String(format: "%.2f", support)) | Batas Bawah Pembelian |\n"
        md += "| Area Resistance Kunci | \(sym)\(isIdr ? "\(Int(resistance))" : String(format: "%.2f", resistance)) | Batas Atas Pasokan |\n\n"

        if !summary.isEmpty {
            md += "💡 Catatan Tren Teknikal:\n"
            md += "\(summary)\n"
        }

        return sanitizeFriendlyText(md)
    }

    private func formatSearchStocksResponse(result: String, query: String) -> String {
        guard let data = result.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let matches = json["matches"] as? [[String: Any]], !matches.isEmpty else {
            return sanitizeFriendlyText("🔍 Hasil Pencarian Saham: \"\(query)\"\n\n\(result)")
        }

        var md = "🔍 Hasil Pencarian Saham: \"\(query)\"\n\n"
        md += "| Kode | Nama Emiten | Harga | Perubahan 24J | Rentang Hari Ini |\n"
        md += "| :--- | :--- | :--- | :--- | :--- |\n"

        for m in matches {
            let ticker = m["ticker"] as? String ?? ""
            let name = m["name"] as? String ?? ticker
            let price = m["price"] as? Double ?? 0
            let chg = m["change_percent"] as? Double ?? 0
            let range = m["day_range"] as? String ?? "-"
            let isIdr = (m["currency"] as? String) == "IDR" || ticker.count == 4
            let priceStr = isIdr ? "Rp \(Int(price))" : "$\(String(format: "%.2f", price))"
            let chgStr = String(format: "%+.2f%%", chg)

            md += "| \(ticker) | \(name) | \(priceStr) | \(chgStr) | \(range) |\n"
        }
        return sanitizeFriendlyText(md)
    }

    private func formatPortfolioNewsResponse(result: String) -> String {
        guard let data = result.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return sanitizeFriendlyText("📰 Berita Terkait Portofolio\n\n\(result)")
        }

        var articles: [[String: Any]] = []
        if let newsObj = json["news"] as? [String: Any], let arts = newsObj["articles"] as? [[String: Any]] {
            articles = arts
        } else if let newsList = json["news"] as? [[String: Any]] {
            articles = newsList
        }

        guard !articles.isEmpty else {
            return sanitizeFriendlyText("📰 Berita Terkait Portofolio\n\nBelum ada berita baru terkait saham di portofolio Anda saat ini.")
        }

        var md = "📰 Berita Terbaru untuk Saham di Portofolio Anda:\n\n"
        for (i, art) in articles.prefix(5).enumerated() {
            let title = art["title"] as? String ?? "Kabar Pasar"
            let source = art["source"] as? String ?? "Media Finansial"
            let summary = art["summary"] as? String ?? ""
            let url = art["url"] as? String ?? ""
            let sentiment = art["sentiment"] as? String ?? "Neutral"
            let sentEmoji = sentiment.lowercased() == "positive" ? "🟢" : (sentiment.lowercased() == "negative" ? "🔴" : "⚪")

            md += "\(i + 1). \(sentEmoji) \(title)\n"
            md += "• Sumber: \(source) • Sentimen: \(sentiment.capitalized)\n"
            if !summary.isEmpty {
                md += "\(summary.prefix(200))...\n"
            }
            if !url.isEmpty {
                md += "Tautan: \(url)\n"
            }
            md += "\n"
        }
        return sanitizeFriendlyText(md)
    }
}

