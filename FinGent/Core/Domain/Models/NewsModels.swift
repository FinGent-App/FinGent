// Core/Domain/Models/NewsModels.swift

import Foundation

// MARK: - News Article Domain Model

struct NewsArticle: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let summary: String?
    let url: URL
    let source: NewsSourceType
    let publishedAt: Date
    let author: String?
    let imageURL: URL?
    let tickers: [String]
    let fetchedAt: Date

    // MARK: - Backward-Compatible Computed Properties

    var date: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: publishedAt)
    }

    var relatedTickers: [String] {
        tickers
    }

    var sentiment: NewsSentiment {
        let text = "\(title) \(summary ?? "")".lowercased()
        let positiveKeywords = ["surges", "soars", "jumps", "rises", "growth", "record", "profit", "gain", "rally", "beat", "buy", "bullish"]
        let negativeKeywords = ["falls", "drops", "slumps", "plunges", "loss", "decline", "weakens", "pressure", "cautious", "sell", "bearish", "miss"]

        let posCount = positiveKeywords.filter { text.contains($0) }.count
        let negCount = negativeKeywords.filter { text.contains($0) }.count

        if posCount > negCount { return .positive }
        if negCount > posCount { return .negative }
        return .neutral
    }

    // MARK: - Initializers

    init(
        id: String,
        title: String,
        summary: String?,
        url: URL,
        source: NewsSourceType,
        publishedAt: Date,
        author: String? = nil,
        imageURL: URL? = nil,
        tickers: [String] = [],
        fetchedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.url = url
        self.source = source
        self.publishedAt = publishedAt
        self.author = author
        self.imageURL = imageURL
        self.tickers = tickers
        self.fetchedAt = fetchedAt
    }

    /// Legacy initializer for backward compatibility with initial mock data
    init(
        id: String,
        title: String,
        source: String,
        date: String,
        summary: String,
        sentiment: NewsSentiment = .neutral,
        relatedTickers: [String]
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.url = URL(string: "https://finance.yahoo.com")!
        self.source = NewsSourceType.from(rawString: source)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        self.publishedAt = formatter.date(from: date) ?? Date()
        self.author = source
        self.imageURL = nil
        self.tickers = relatedTickers
        self.fetchedAt = Date()
    }
}

// MARK: - News Sentiment

enum NewsSentiment: String, Codable, Sendable {
    case positive
    case negative
    case neutral

    var emoji: String {
        switch self {
        case .positive: return "🟢"
        case .negative: return "🔴"
        case .neutral: return "⚪"
        }
    }

    var label: String {
        switch self {
        case .positive: return "positive"
        case .negative: return "cautious"
        case .neutral: return "neutral"
        }
    }
}

// MARK: - News Citation (For AI Responses)

struct NewsCitation: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let source: NewsSourceType
    let url: URL
    let publishedAt: Date
    let badgeLabel: String?

    init(from article: NewsArticle) {
        self.id = article.id
        self.title = article.title
        self.source = article.source
        self.url = article.url
        self.publishedAt = article.publishedAt
        self.badgeLabel = nil
    }

    init(id: String, title: String, source: NewsSourceType, url: URL, publishedAt: Date, badgeLabel: String? = nil) {
        self.id = id
        self.title = title
        self.source = source
        self.url = url
        self.publishedAt = publishedAt
        self.badgeLabel = badgeLabel
    }
}

// MARK: - Market Bias

enum MarketBias: String, Codable, Sendable {
    case bullish
    case bearish
    case neutral

    var label: String {
        switch self {
        case .bullish: return "Bullish"
        case .bearish: return "Bearish"
        case .neutral: return "Neutral"
        }
    }

    var emoji: String {
        switch self {
        case .bullish: return "🟢"
        case .bearish: return "🔴"
        case .neutral: return "⚪"
        }
    }
}

// MARK: - Structured AI Response Contract

struct AIResponse: Codable, Sendable {
    let answer: String
    let bias: MarketBias?
    let confidence: Double?
    let sources: [NewsCitation]

    init(
        answer: String,
        bias: MarketBias? = nil,
        confidence: Double? = nil,
        sources: [NewsCitation] = []
    ) {
        self.answer = answer
        self.bias = bias
        self.confidence = confidence
        self.sources = sources
    }
}

// MARK: - News Query Context

struct NewsQueryContext: Equatable, Sendable {
    let tickers: [String]
    let timeRange: DateInterval
    let requiresNews: Bool
    let queryType: QueryType

    enum QueryType: String, Sendable {
        case stockOutlook
        case newsCatalyst
        case generalMarket
        case generalConcept
    }
}
