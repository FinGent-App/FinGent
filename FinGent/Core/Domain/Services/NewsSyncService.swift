// Core/Domain/Services/NewsSyncService.swift

import Foundation
import os

actor NewsSyncService {

    static let shared = NewsSyncService()

    private let sources: [NewsSource]
    private let yahooSource: YahooFinanceNewsSource
    private let repository: NewsRepositoryProtocol
    private let extractor: TickerExtractor

    private var lastSyncTime: Date?
    private let cacheTTL: TimeInterval = 600 // 10 minutes
    private var isSyncing: Bool = false

    private let logger = Logger(subsystem: "com.suryacenter.FinGent", category: "NewsSyncService")

    init(
        sources: [NewsSource]? = nil,
        repository: NewsRepositoryProtocol = NewsRepository.shared,
        extractor: TickerExtractor = StockTickerExtractor()
    ) {
        let yahoo = YahooFinanceNewsSource()
        let cnbc = CNBCNewsSource()
        self.yahooSource = yahoo
        self.sources = sources ?? [yahoo, cnbc]
        self.repository = repository
        self.extractor = extractor
    }

    // MARK: - Periodic / Background Sync

    func sync(force: Bool = false) async {
        if !force, let last = lastSyncTime, Date().timeIntervalSince(last) < cacheTTL {
            return
        }

        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        var allFetched: [NewsArticle] = []

        await withTaskGroup(of: [NewsArticle]?.self) { group in
            for source in sources {
                group.addTask {
                    do {
                        return try await source.fetchArticles()
                    } catch {
                        return nil
                    }
                }
            }

            for await result in group {
                if let articles = result {
                    allFetched.append(contentsOf: articles)
                }
            }
        }

        // Ticker extraction for articles
        let enriched = allFetched.map { article -> NewsArticle in
            let detected = self.extractor.extractTickers(from: article)
            let combinedTickers = Array(Set(article.tickers + detected)).sorted()
            return NewsArticle(
                id: article.id,
                title: article.title,
                summary: article.summary,
                url: article.url,
                source: article.source,
                publishedAt: article.publishedAt,
                author: article.author,
                imageURL: article.imageURL,
                tickers: combinedTickers,
                fetchedAt: Date()
            )
        }

        if !enriched.isEmpty {
            try? await repository.save(enriched)
            lastSyncTime = Date()
        }
    }

    // MARK: - On-Demand Ticker Sync

    func syncTicker(ticker: String) async {
        let cleanTicker = ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanTicker.isEmpty else { return }

        do {
            let tickerArticles = try await yahooSource.fetchArticles(for: cleanTicker)
            let enriched = tickerArticles.map { article -> NewsArticle in
                let detected = self.extractor.extractTickers(from: article)
                let combined = Array(Set(article.tickers + detected + [cleanTicker])).sorted()
                return NewsArticle(
                    id: article.id,
                    title: article.title,
                    summary: article.summary,
                    url: article.url,
                    source: article.source,
                    publishedAt: article.publishedAt,
                    author: article.author,
                    imageURL: article.imageURL,
                    tickers: combined,
                    fetchedAt: Date()
                )
            }

            if !enriched.isEmpty {
                try? await repository.save(enriched)
            }
        } catch {
            logger.warning("Failed on-demand ticker news sync for \(cleanTicker): \(error.localizedDescription)")
        }
    }
}
