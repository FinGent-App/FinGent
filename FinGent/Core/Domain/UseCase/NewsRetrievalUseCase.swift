// Core/Domain/UseCase/NewsRetrievalUseCase.swift

import Foundation

// MARK: - Query Analyzer

final class QueryAnalyzer: Sendable {

    private let extractor: TickerExtractor

    init(extractor: TickerExtractor = StockTickerExtractor()) {
        self.extractor = extractor
    }

    func analyze(prompt: String) -> NewsQueryContext {
        let lowered = prompt.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let detectedTickers = extractor.extractTickers(from: prompt)

        // Check for educational / conceptual queries that do NOT need news
        let conceptualPatterns = [
            "apa itu", "what is", "jelaskan", "explain", "bagaimana cara membaca",
            "pengertian", "definisi", "definition of", "how does a", "rumus", "formula"
        ]
        let isConceptual = conceptualPatterns.contains { lowered.contains($0) } && detectedTickers.isEmpty

        if isConceptual {
            return NewsQueryContext(
                tickers: [],
                timeRange: DateInterval(start: Date().addingTimeInterval(-3600 * 24 * 7), end: Date()),
                requiresNews: false,
                queryType: .generalConcept
            )
        }

        // Check for news catalysts or market questions
        let newsKeywords = [
            "berita", "news", "katalis", "catalyst", "hari ini", "today", "minggu ini", "this week",
            "naik", "turun", "up", "down", "prospek", "outlook", "bullish", "bearish",
            "kinerja", "laba", "earnings", "drop", "surge", "kenapa", "why", "bagaimana"
        ]
        let mentionsNews = newsKeywords.contains { lowered.contains($0) }

        let requiresNews = !detectedTickers.isEmpty || mentionsNews || lowered.contains("pasar") || lowered.contains("market")

        // Determine timeframe
        let hours: Double
        if lowered.contains("hari ini") || lowered.contains("today") || lowered.contains("sekarang") {
            hours = 24
        } else if lowered.contains("minggu ini") || lowered.contains("this week") {
            hours = 24 * 7
        } else {
            hours = 24 * 3 // default 3 days
        }

        let timeRange = DateInterval(start: Date().addingTimeInterval(-3600 * hours), end: Date())

        let type: NewsQueryContext.QueryType
        if !detectedTickers.isEmpty && (lowered.contains("naik") || lowered.contains("turun") || lowered.contains("prospek")) {
            type = .stockOutlook
        } else if lowered.contains("katalis") || lowered.contains("berita") {
            type = .newsCatalyst
        } else if detectedTickers.isEmpty {
            type = .generalMarket
        } else {
            type = .stockOutlook
        }

        return NewsQueryContext(
            tickers: detectedTickers,
            timeRange: timeRange,
            requiresNews: requiresNews,
            queryType: type
        )
    }
}

// MARK: - News Ranking Service

final class NewsRankingService: Sendable {

    func rank(articles: [NewsArticle], for context: NewsQueryContext, userPrompt: String) -> [NewsArticle] {
        let promptTokens = userPrompt.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }

        let now = Date()

        let scored: [(article: NewsArticle, score: Double)] = articles.map { article in
            var score: Double = 0.0

            // 1. Ticker match score
            let articleTickers = Set(article.tickers.map { $0.uppercased() })
            for target in context.tickers {
                let upperTarget = target.uppercased()
                if articleTickers.contains(upperTarget) {
                    score += 50.0
                }
                if article.title.uppercased().contains(upperTarget) {
                    score += 30.0
                }
            }

            // 2. Keyword relevance score
            let titleLowered = article.title.lowercased()
            let summaryLowered = (article.summary ?? "").lowercased()
            for token in promptTokens {
                if titleLowered.contains(token) {
                    score += 15.0
                } else if summaryLowered.contains(token) {
                    score += 8.0
                }
            }

            // 3. Recency score
            let hoursOld = max(0, now.timeIntervalSince(article.publishedAt) / 3600.0)
            if hoursOld <= 24 {
                score += 30.0
            } else if hoursOld <= 72 {
                score += 20.0
            } else if hoursOld <= 168 {
                score += 10.0
            }

            // 4. Source score
            if article.source == .yahooFinance || article.source == .cnbc || article.source == .sec {
                score += 10.0
            }

            return (article, score)
        }

        return scored
            .sorted { $0.score > $1.score }
            .map { $0.article }
    }
}

// MARK: - NewsRetrievalUseCase Protocol & Implementation

protocol NewsRetrievalUseCaseProtocol: Sendable {
    func retrieveNews(for prompt: String) async -> (context: NewsQueryContext, articles: [NewsArticle])
}

final class NewsRetrievalUseCase: NewsRetrievalUseCaseProtocol {

    private let queryAnalyzer: QueryAnalyzer
    private let newsRepository: NewsRepositoryProtocol
    private let syncService: NewsSyncService
    private let rankingService: NewsRankingService

    init(
        queryAnalyzer: QueryAnalyzer = QueryAnalyzer(),
        newsRepository: NewsRepositoryProtocol = NewsRepository.shared,
        syncService: NewsSyncService = NewsSyncService.shared,
        rankingService: NewsRankingService = NewsRankingService()
    ) {
        self.queryAnalyzer = queryAnalyzer
        self.newsRepository = newsRepository
        self.syncService = syncService
        self.rankingService = rankingService
    }

    func retrieveNews(for prompt: String) async -> (context: NewsQueryContext, articles: [NewsArticle]) {
        let context = queryAnalyzer.analyze(prompt: prompt)

        guard context.requiresNews else {
            return (context, [])
        }

        // Trigger on-demand sync for detected tickers if any
        if let firstTicker = context.tickers.first {
            await syncService.syncTicker(ticker: firstTicker)
        } else {
            await syncService.sync()
        }

        // Fetch candidate articles from repository
        let candidates: [NewsArticle]
        if let ticker = context.tickers.first {
            candidates = (try? await newsRepository.articles(
                ticker: ticker,
                from: nil,
                to: nil,
                source: nil,
                limit: 20
            )) ?? newsRepository.getArticles(for: [ticker])
        } else {
            candidates = (try? await newsRepository.articles(
                ticker: nil,
                from: context.timeRange.start,
                to: context.timeRange.end,
                source: nil,
                limit: 20
            )) ?? newsRepository.allArticles
        }

        // Rank articles by relevance
        let ranked = rankingService.rank(articles: candidates, for: context, userPrompt: prompt)
        let topArticles = Array(ranked.prefix(4))

        return (context, topArticles)
    }
}
