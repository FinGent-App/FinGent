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

        // Case 1: Conceptual or general queries that do not need news evidence
        guard context.requiresNews && !articles.isEmpty else {
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

        // Case 2: News Grounded Prompt Construction
        let groundedPrompt = buildGroundedPrompt(
            userPrompt: prompt,
            context: context,
            articles: articles
        )

        let citations = articles.map { NewsCitation(from: $0) }

        do {
            let rawReply = try await agent.askGrounded(groundedPrompt)
            let (cleanedAnswer, bias) = extractBias(from: rawReply)

            return AIResponse(
                answer: cleanedAnswer,
                bias: bias,
                confidence: bias != nil ? 0.78 : nil,
                sources: citations
            )
        } catch {
            // Graceful fallback synthesis if on-device model hits GenerationError or context limit
            let fallback = synthesizeFallbackResponse(
                userPrompt: prompt,
                context: context,
                articles: articles
            )

            return AIResponse(
                answer: fallback.answer,
                bias: fallback.bias,
                confidence: 0.75,
                sources: citations
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
        articles: [NewsArticle]
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

        // Add structured news evidence (concise top articles to stay well within token limits)
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

        // Strict grounding instructions
        prompt += """
        STRICT GROUNDING INSTRUCTIONS:
        1. Base your answer strictly on the NEWS EVIDENCE and MARKET DATA provided above. Do NOT fabricate or assume unreported news.
        2. Clearly distinguish between:
           - FACTS: What the latest news explicitly reported (with timestamps/freshness).
           - ANALYSIS: What these facts imply for the company and market.
           - OUTLOOK / BIAS: State a clear probabilistic bias (Bullish, Bearish, or Neutral). Never state that a stock is certain to rise or fall.
        3. If the evidence is insufficient to make a strong prediction, explicitly state that recent news evidence is limited.
        4. Provide an actionable, well-reasoned answer in natural, friendly tone.
        5. At the very end of your response, output a single bias tag on a new line:
           [BIAS: BULLISH] or [BIAS: BEARISH] or [BIAS: NEUTRAL].
        """

        return prompt
    }

    // MARK: - Fallback Synthesis (When on-device LLM hits GenerationError / asset limits)

    private func synthesizeFallbackResponse(
        userPrompt: String,
        context: NewsQueryContext,
        articles: [NewsArticle]
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

        var text = "Berdasarkan bukti berita terkini dari **Yahoo Finance** dan **CNBC**, bias pergerakan saham **\(ticker)** saat ini cenderung **\(bias.label)**.\n\n"

        if let q = quote {
            text += "📊 **Kondisi Pasar Terkini:**\nHarga berada di **\(q.formattedPrice)** dengan pergerakan harian **\(q.formattedChange)** (\(String(format: "%.2f", q.changePercent))%).\n\n"
        }

        text += "📰 **Fakta & Katalis dari Berita Terbaru:**\n"
        for (i, article) in articles.prefix(3).enumerated() {
            let relativeTime = article.publishedAt.timeAgoDisplay()
            text += "\(i + 1). **\(article.title)** (\(article.source.displayName), \(relativeTime))\n"
            if let summary = article.summary, !summary.isEmpty {
                text += "   _\(summary)_\n"
            }
        }

        text += "\n💡 **Analisis & Outlook:**\n"
        switch bias {
        case .bullish:
            text += "Katalis berita terbaru menunjukkan sentimen yang konstruktif dan permintaan yang solid. Namun, pergerakan jangka pendek tetap bergantung pada likuiditas pasar dan sentimen makroekonomi."
        case .bearish:
            text += "Berita terkini mengindikasikan adanya tekanan jangka pendek atau kehati-hatian investor terhadap sektor ini. Disarankan untuk memantau level *support* kunci."
        case .neutral:
            text += "Belum ada katalis tunggal yang dominan untuk memicu tren arah baru. Pergerakan harga diperkirakan masih bergerak dalam fase konsolidasi."
        }

        text += "\n\n*(Catatan: Ini adalah sintesis berbasis bukti berita terkini dan bukan jaminan pasti arah pergerakan harga).*"

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
