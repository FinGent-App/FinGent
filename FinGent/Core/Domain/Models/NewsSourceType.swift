// Core/Domain/Models/NewsSourceType.swift

import Foundation

enum NewsSourceType: String, Codable, CaseIterable, Sendable, Hashable, CustomStringConvertible {
    case yahooFinance = "Yahoo Finance"
    case cnbc = "CNBC"
    case sec = "SEC"
    case portfolio = "Portfolio"
    case bloomberg = "Bloomberg"
    case reuters = "Reuters"
    case other = "Other"

    var description: String { displayName }

    var displayName: String {
        switch self {
        case .yahooFinance: return "Yahoo Finance"
        case .cnbc: return "CNBC"
        case .sec: return "SEC Filing"
        case .portfolio: return "Portofolio & P/L"
        case .bloomberg: return "Bloomberg"
        case .reuters: return "Reuters"
        case .other: return "News"
        }
    }

    var iconSystemName: String {
        switch self {
        case .yahooFinance: return "newspaper.fill"
        case .cnbc: return "chart.bar.xaxis"
        case .sec: return "doc.text.fill"
        case .portfolio: return "briefcase.fill"
        case .bloomberg: return "globe.americas.fill"
        case .reuters: return "antenna.radiowaves.left.and.right"
        case .other: return "link"
        }
    }

    var assetImageName: String {
        switch self {
        case .yahooFinance: return "logo_yahoo"
        case .cnbc: return "logo_cnbc"
        case .sec: return "logo_sec"
        case .portfolio: return "logo_portfolio"
        case .bloomberg: return "logo_bloomberg"
        case .reuters: return "logo_reuters"
        case .other: return "logo_news"
        }
    }

    var shortBadge: String {
        switch self {
        case .yahooFinance: return "Y!"
        case .cnbc: return "CNBC"
        case .sec: return "SEC"
        case .portfolio: return "P"
        case .bloomberg: return "BBG"
        case .reuters: return "R"
        case .other: return "N"
        }
    }

    var accentHex: String {
        switch self {
        case .yahooFinance: return "722EE5" // Purple
        case .cnbc: return "0D8CD9" // Blue
        case .sec: return "EAA626" // Gold
        case .portfolio: return "00D084" // Emerald Green
        case .bloomberg: return "FF5933" // Orange
        case .reuters: return "FF8000" // Tangerine
        case .other: return "8E8E93" // Gray
        }
    }

    static func from(rawString: String) -> NewsSourceType {
        let lowered = rawString.lowercased()
        if lowered.contains("portfolio") || lowered.contains("portofolio") {
            return .portfolio
        } else if lowered.contains("sec") {
            return .sec
        } else if lowered.contains("yahoo") {
            return .yahooFinance
        } else if lowered.contains("cnbc") {
            return .cnbc
        } else if lowered.contains("bloomberg") {
            return .bloomberg
        } else if lowered.contains("reuters") {
            return .reuters
        }
        return .other
    }
}
