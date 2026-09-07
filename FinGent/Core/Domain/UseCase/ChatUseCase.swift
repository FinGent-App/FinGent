// Core/Domain/UseCase/ChatUseCase.swift

import Foundation

// MARK: - ChatUseCaseProtocol

@MainActor
protocol ChatUseCaseProtocol: Sendable {
    func ask(_ prompt: String) async throws -> AIResponse
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
        let (context, articles) = await newsRetrievalUseCase.retrieveNews(for: prompt)

        // 1. Fetch Zilliz Cloud Milvus RAG knowledge (SEC, Portfolio & P/L, News)
        let ragTargetTicker = context.tickers.first
        let ragResponse = try? await StockApiClient.shared.queryRAG(prompt: prompt, ticker: ragTargetTicker)

        var allCitations: [NewsCitation] = []

        if let ragHits = ragResponse?.citations, !ragHits.isEmpty {
            for dto in ragHits {
                let source: NewsSourceType
                if dto.doc_type == "portfolio" {
                    source = .portfolio
                } else if dto.doc_type == "sec" {
                    source = .sec
                } else {
                    source = NewsSourceType.from(rawString: dto.badge_label)
                }
                allCitations.append(
                    NewsCitation(
                        id: dto.id,
                        title: dto.title,
                        source: source,
                        url: URL(string: dto.source_url) ?? URL(string: "about:blank")!,
                        publishedAt: Date(),
                        badgeLabel: dto.badge_label
                    )
                )
            }
        }

        // Also merge local RSS articles if any
        for art in articles {
            if !allCitations.contains(where: { $0.title == art.title }) {
                allCitations.append(NewsCitation(from: art))
            }
        }

        // Case 1: Conceptual or general queries that do not have RAG knowledge nor news
        guard !allCitations.isEmpty || (context.requiresNews && !articles.isEmpty) else {
            do {
                let rawReply = try await agent.ask(prompt)
                return AIResponse(
                    answer: rawReply,
                    bias: nil,
                    confidence: nil,
                    sources: []
                )
            } catch {
                return AIResponse(
                    answer: "FinGent siap membantu analisis pasar dan portofolio Anda. Coba tanyakan prospek saham spesifik seperti: \"Apakah MU akan naik atau turun?\" atau \"Katalis terbaru NVDA\".",
                    bias: nil,
                    confidence: nil,
                    sources: []
                )
            }
        }

        // Case 2: Evidence Grounded Prompt Construction (Zilliz Milvus + RSS)
        let groundedPrompt = buildGroundedPrompt(
            userPrompt: prompt,
            context: context,
            articles: articles,
            ragGrounding: ragResponse?.grounding_context
        )

        do {
            let rawReply = try await agent.askGrounded(groundedPrompt)
            let (cleanedAnswer, bias) = extractBias(from: rawReply)

            return AIResponse(
                answer: cleanedAnswer,
                bias: bias,
                confidence: bias != nil ? 0.78 : nil,
                sources: allCitations
            )
        } catch {
            // Graceful fallback synthesis if on-device model hits GenerationError or context limit
            let fallback = synthesizeFallbackResponse(
                userPrompt: prompt,
                context: context,
                articles: articles,
                ragCitations: allCitations
            )

            return AIResponse(
                answer: fallback.answer,
                bias: fallback.bias,
                confidence: 0.75,
                sources: allCitations
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
        ragGrounding: String? = nil
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
        1. Base your answer strictly on the VERIFIED FINANCIAL KNOWLEDGE BASE, NEWS EVIDENCE, and MARKET DATA provided above. Do NOT fabricate or assume unreported information.
        2. Reference user's portfolio holding or SEC filing directly if present in the knowledge base.
        3. Clearly distinguish between:
           - FACTS: What the verified knowledge base and latest news explicitly report.
           - ANALYSIS: What these facts imply for the company, user's position, and market.
           - OUTLOOK / BIAS: State a clear probabilistic bias (Bullish, Bearish, or Neutral). Never state that a stock is certain to rise or fall.
        4. Provide an actionable, well-reasoned answer in Indonesian (natural, friendly, professional tone).
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
        ragCitations: [NewsCitation] = []
    ) -> (answer: String, bias: MarketBias) {
        let ticker = context.tickers.first ?? "Pasar"
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

        var text = "Berdasarkan analisis terintegrasi **FinGent Intelligence (Zilliz Cloud RAG & Live Market)**, berikut ringkasan untuk **\(ticker)**:\n\n"

        if let q = quote {
            text += "📊 **Kondisi Pasar Terkini:**\nHarga berada di **\(q.formattedPrice)** dengan pergerakan harian **\(q.formattedChange)** (\(String(format: "%.2f", q.changePercent))%).\n\n"
        }

        // Display Portfolio Citations if available
        let portfolioCitations = ragCitations.filter { $0.source == .portfolio }
        if !portfolioCitations.isEmpty {
            text += "💼 **Posisi Portofolio Anda:**\n"
            for p in portfolioCitations {
                text += "• \(p.title)\n"
            }
            text += "\n"
        }

        // Display SEC Citations if available
        let secCitations = ragCitations.filter { $0.source == .sec }
        if !secCitations.isEmpty {
            text += "🏛️ **Laporan Resmi SEC (EDGAR/Yahoo):**\n"
            for s in secCitations {
                text += "• \(s.badgeLabel ?? "SEC Filing"): \(s.title)\n"
            }
            text += "\n"
        }

        // Display News Citations if available
        if !articles.isEmpty {
            text += "📰 **Fakta & Katalis dari Berita Terbaru:**\n"
            for (i, article) in articles.prefix(3).enumerated() {
                let relativeTime = article.publishedAt.timeAgoDisplay()
                text += "\(i + 1). **\(article.title)** (\(article.source.displayName), \(relativeTime))\n"
                if let summary = article.summary, !summary.isEmpty {
                    text += "   _\(summary)_\n"
                }
            }
        }

        text += "\n💡 **Analisis & Outlook:**\n"
        switch bias {
        case .bullish:
            text += "Katalis berita dan fundamental terkini menunjukkan sentimen yang konstruktif. Namun, pergerakan jangka pendek tetap bergantung pada likuiditas pasar."
        case .bearish:
            text += "Data terkini mengindikasikan adanya kehati-hatian investor atau potensi koreksi jangka pendek. Disarankan untuk memantau level proteksi risiko."
        case .neutral:
            text += "Kondisi pasar saat ini berada dalam fase konsolidasi seimbang tanpa dorongan arah ekstrem."
        }

        text += "\n\n*(Catatan: Rangkuman disintesis dari Zilliz Milvus Vector RAG, SEC Filings, dan Live News feeds).*"

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
