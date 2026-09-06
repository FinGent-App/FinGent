// Core/Domain/Models/NewsModels.swift

import Foundation

struct NewsArticle: Sendable {
    let id: String
    let title: String
    let source: String
    let date: String
    let summary: String
    let sentiment: NewsSentiment
    let relatedTickers: [String]
}

enum NewsSentiment: String, Sendable {
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
