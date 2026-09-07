// Core/Data/Repository/NewsRepository.swift

import Foundation

final class NewsRepository: NewsRepositoryProtocol, @unchecked Sendable {

    static let shared = NewsRepository()

    private enum Key {
        static let cachedArticles = "cached_rss_news_articles"
    }

    private let lock = NSLock()
    private var articlesStorage: [NewsArticle] = []

    var allArticles: [NewsArticle] {
        lock.lock()
        defer { lock.unlock() }
        return articlesStorage
    }

    private init() {
        self.articlesStorage = Self.loadPersistedArticles()
        if self.articlesStorage.isEmpty {
            self.articlesStorage = Self.initialSeedArticles
        }
    }

    // MARK: - Save & Ingest (Deduplicate & Sort by Published Date)

    func save(_ articles: [NewsArticle]) async throws {
        lock.lock()
        defer { lock.unlock() }

        var existingMap: [String: NewsArticle] = [:]
        for art in articlesStorage {
            existingMap[art.id] = art
        }

        // Insert or update
        for newArt in articles {
            if let existing = existingMap[newArt.id] {
                // Merge tickers if any new ones detected
                let mergedTickers = Array(Set(existing.tickers + newArt.tickers)).sorted()
                existingMap[newArt.id] = NewsArticle(
                    id: existing.id,
                    title: newArt.title.isEmpty ? existing.title : newArt.title,
                    summary: newArt.summary ?? existing.summary,
                    url: newArt.url,
                    source: newArt.source,
                    publishedAt: newArt.publishedAt,
                    author: newArt.author ?? existing.author,
                    imageURL: newArt.imageURL ?? existing.imageURL,
                    tickers: mergedTickers,
                    fetchedAt: newArt.fetchedAt
                )
            } else {
                existingMap[newArt.id] = newArt
            }
        }

        // Keep sorted by publishedAt descending, cap at max 200 articles
        self.articlesStorage = existingMap.values
            .sorted { $0.publishedAt > $1.publishedAt }
            .prefix(200)
            .map { $0 }

        Self.persistArticles(self.articlesStorage)
    }

    // MARK: - Filter Query

    func articles(
        ticker: String?,
        from: Date?,
        to: Date?,
        source: NewsSourceType?,
        limit: Int = 10
    ) async throws -> [NewsArticle] {
        lock.lock()
        let snapshot = articlesStorage
        lock.unlock()

        let filtered = snapshot.filter { article in
            if let t = ticker?.uppercased(), !t.isEmpty {
                let hasTicker = article.tickers.contains(t) ||
                    article.title.uppercased().contains(t) ||
                    (article.summary?.uppercased().contains(t) ?? false)
                if !hasTicker { return false }
            }

            if let fromDate = from, article.publishedAt < fromDate {
                return false
            }

            if let toDate = to, article.publishedAt > toDate {
                return false
            }

            if let src = source, article.source != src {
                return false
            }

            return true
        }

        return Array(filtered.prefix(limit))
    }

    // MARK: - Search & Legacy Helpers

    func searchArticles(query: String) -> [NewsArticle] {
        let lowered = query.lowercased().trimmingCharacters(in: .whitespaces)
        lock.lock()
        let snapshot = articlesStorage
        lock.unlock()

        guard !lowered.isEmpty else { return snapshot }

        let stopWords: Set<String> = ["my", "about", "the", "a", "an", "is", "there", "any",
                                      "news", "berita", "saham", "stock", "holding", "holdings"]
        let keywords = lowered
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !stopWords.contains($0) }

        return snapshot.filter { article in
            let title = article.title.lowercased()
            let summary = (article.summary ?? "").lowercased()
            let tickers = article.tickers.map { $0.lowercased() }

            if title.contains(lowered) || summary.contains(lowered) || tickers.contains(lowered) {
                return true
            }
            return keywords.contains { word in
                tickers.contains(word) || title.contains(word) || summary.contains(word)
            }
        }
    }

    func getArticles(for tickers: [String]) -> [NewsArticle] {
        let upperTickers = Set(tickers.map { $0.uppercased() })
        lock.lock()
        let snapshot = articlesStorage
        lock.unlock()

        return snapshot.filter { article in
            let articleTickers = Set(article.tickers.map { $0.uppercased() })
            if !articleTickers.isDisjoint(with: upperTickers) {
                return true
            }
            // Check if ticker is directly mentioned in title or summary
            for t in upperTickers {
                if article.title.contains(t) || (article.summary?.contains(t) ?? false) {
                    return true
                }
            }
            return false
        }
    }

    // MARK: - Persistence

    private static func persistArticles(_ articles: [NewsArticle]) {
        guard let data = try? JSONEncoder().encode(articles) else { return }
        UserDefaults.standard.set(data, forKey: Key.cachedArticles)
    }

    private static func loadPersistedArticles() -> [NewsArticle] {
        guard
            let data = UserDefaults.standard.data(forKey: Key.cachedArticles),
            let articles = try? JSONDecoder().decode([NewsArticle].self, from: data)
        else { return [] }
        return articles
    }

    // MARK: - Seed Articles (Fallback if Offline)

    private static var initialSeedArticles: [NewsArticle] {
        [
            NewsArticle(
                id: "seed-1",
                title: "Bank Indonesia Holds Interest Rate at 5.75%, Supports Rupiah Stability",
                summary: "Bank Indonesia maintained its benchmark interest rate at 5.75% for the third consecutive month, citing the need to stabilize the rupiah exchange rate amid global uncertainty.",
                url: URL(string: "https://www.cnbcindonesia.com/market/bank-indonesia-rate")!,
                source: .cnbc,
                publishedAt: Date().addingTimeInterval(-3600 * 24 * 2),
                tickers: ["BBCA", "BBRI", "BMRI"]
            ),
            NewsArticle(
                id: "seed-2",
                title: "BBCA Reports Record Q2 Net Profit of Rp 13.2 Trillion",
                summary: "Bank Central Asia recorded its highest-ever quarterly net profit of Rp 13.2 trillion in Q2 2026, driven by strong loan growth of 12% YoY and improved net interest margin.",
                url: URL(string: "https://finance.yahoo.com/news/bbca-record-profit")!,
                source: .yahooFinance,
                publishedAt: Date().addingTimeInterval(-3600 * 24 * 3),
                tickers: ["BBCA"]
            ),
            NewsArticle(
                id: "seed-3",
                title: "GoTo Achieves First Full-Year Profitability, Stock Surges",
                summary: "GoTo Gojek Tokopedia reported its first full-year EBITDA profitability, marking a significant milestone for Indonesia's tech sector. The stock jumped 5% on the news.",
                url: URL(string: "https://finance.yahoo.com/news/goto-profitability")!,
                source: .yahooFinance,
                publishedAt: Date().addingTimeInterval(-3600 * 24 * 3),
                tickers: ["GOTO", "EMTK"]
            ),
            NewsArticle(
                id: "seed-4",
                title: "Micron Technology (MU) Surges on High-Bandwidth Memory AI Demand",
                summary: "Micron shares rallied after management raised its fiscal guidance, pointing to unprecedented demand for HBM3E chips powering next-generation AI accelerators.",
                url: URL(string: "https://finance.yahoo.com/news/micron-ai-demand-hbm3e")!,
                source: .yahooFinance,
                publishedAt: Date().addingTimeInterval(-3600 * 4),
                tickers: ["MU", "NVDA"]
            ),
            NewsArticle(
                id: "seed-5",
                title: "NVIDIA (NVDA) Blackwell Architecture Production Ramps Up Ahead of Schedule",
                summary: "Nvidia CEO confirmed full-scale production ramp for Blackwell GPUs with strong cloud provider adoption across Microsoft, Amazon, and Google.",
                url: URL(string: "https://www.cnbc.com/2026/09/06/nvidia-blackwell-production-ramp.html")!,
                source: .cnbc,
                publishedAt: Date().addingTimeInterval(-3600 * 8),
                tickers: ["NVDA", "MSFT", "AMZN", "GOOGL"]
            )
        ]
    }
}
