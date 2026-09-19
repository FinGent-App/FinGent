// Core/Data/Network/RSS/NewsSource.swift

import Foundation

// MARK: - NewsSource Protocol

protocol NewsSource: Sendable {
    var source: NewsSourceType { get }
    var sourceName: String { get }
    var feedURL: URL { get }
    func fetchArticles() async throws -> [NewsArticle]
}

// MARK: - Yahoo Finance News Source

final class YahooFinanceNewsSource: NewsSource {
    let source: NewsSourceType = .yahooFinance
    var sourceName: String { source.displayName }
    let feedURL: URL

    private let session: URLSession

    init(
        feedURL: URL = URL(string: "https://finance.yahoo.com/news/rssindex")!,
        session: URLSession = .shared
    ) {
        self.feedURL = feedURL
        self.session = session
    }

    func fetchArticles() async throws -> [NewsArticle] {
        try await fetch(from: feedURL)
    }

    /// On-demand fetch for a specific stock ticker headline feed
    func fetchArticles(for ticker: String) async throws -> [NewsArticle] {
        let cleanTicker = ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let tickerURL = URL(string: "https://feeds.finance.yahoo.com/rss/2.0/headline?s=\(cleanTicker)") else {
            return []
        }
        var articles = try await fetch(from: tickerURL)
        // Tag with requested ticker if not already tagged
        for i in 0..<articles.count {
            if !articles[i].tickers.contains(cleanTicker) {
                var currentTickers = articles[i].tickers
                currentTickers.append(cleanTicker)
                articles[i] = NewsArticle(
                    id: articles[i].id,
                    title: articles[i].title,
                    summary: articles[i].summary,
                    url: articles[i].url,
                    source: articles[i].source,
                    publishedAt: articles[i].publishedAt,
                    author: articles[i].author,
                    imageURL: articles[i].imageURL,
                    tickers: currentTickers,
                    fetchedAt: articles[i].fetchedAt
                )
            }
        }
        return articles
    }

    private func fetch(from url: URL) async throws -> [NewsArticle] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("application/rss+xml, text/xml, */*", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw URLError(.badServerResponse)
        }

        let parser = RSSParser(defaultSource: .yahooFinance)
        return parser.parse(data: data)
    }
}

// MARK: - CNBC News Source

final class CNBCNewsSource: NewsSource {
    let source: NewsSourceType = .cnbc
    var sourceName: String { source.displayName }
    let feedURL: URL

    private let session: URLSession

    init(
        feedURL: URL = URL(string: "https://www.cnbc.com/id/10000664/device/rss/rss.html")!,
        session: URLSession = .shared
    ) {
        self.feedURL = feedURL
        self.session = session
    }

    func fetchArticles() async throws -> [NewsArticle] {
        var request = URLRequest(url: feedURL)
        request.timeoutInterval = 10
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("application/rss+xml, text/xml, */*", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw URLError(.badServerResponse)
        }

        let parser = RSSParser(defaultSource: .cnbc)
        return parser.parse(data: data)
    }
}

// MARK: - Generic RSS News Source (Supports Investing.com, Nasdaq, Kontan, Detik, etc.)

final class GenericRSSNewsSource: NewsSource {
    let source: NewsSourceType
    var sourceName: String { source.displayName }
    let feedURL: URL

    private let session: URLSession

    init(
        source: NewsSourceType,
        feedURL: URL,
        session: URLSession = .shared
    ) {
        self.source = source
        self.feedURL = feedURL
        self.session = session
    }

    func fetchArticles() async throws -> [NewsArticle] {
        var request = URLRequest(url: feedURL)
        request.timeoutInterval = 10
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("application/rss+xml, text/xml, */*", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw URLError(.badServerResponse)
        }

        let parser = RSSParser(defaultSource: source)
        return parser.parse(data: data)
    }
}

