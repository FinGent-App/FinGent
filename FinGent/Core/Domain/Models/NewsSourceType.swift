// Core/Domain/Models/NewsSourceType.swift

import Foundation

enum NewsSourceType: String, Codable, CaseIterable, Sendable, Hashable, CustomStringConvertible {
    // US & Global Financial Sources
    case yahooFinance = "Yahoo Finance"
    case cnbc = "CNBC"
    case investing = "Investing.com"
    case nasdaq = "Nasdaq"
    case globeNewswire = "GlobeNewswire"
    case prNewswire = "PR Newswire"
    case businessWire = "Business Wire"
    case bloomberg = "Bloomberg"
    case reuters = "Reuters"

    // Indonesian IDX Financial Sources
    case kontan = "Kontan"
    case detikFinance = "Detik Finance"
    case liputan6 = "Liputan6 Bisnis"
    case tempo = "Tempo Bisnis"
    case cnnIndonesia = "CNN Indonesia Ekonomi"

    // Regulatory & Portfolio
    case sec = "SEC"
    case portfolio = "Portfolio"
    case other = "Other"

    var description: String { displayName }

    var displayName: String {
        switch self {
        case .yahooFinance: return "Yahoo Finance"
        case .cnbc: return "CNBC"
        case .investing: return "Investing.com"
        case .nasdaq: return "Nasdaq"
        case .globeNewswire: return "GlobeNewswire"
        case .prNewswire: return "PR Newswire"
        case .businessWire: return "Business Wire"
        case .bloomberg: return "Bloomberg"
        case .reuters: return "Reuters"
        case .kontan: return "Kontan"
        case .detikFinance: return "Detik Finance"
        case .liputan6: return "Liputan6 Bisnis"
        case .tempo: return "Tempo Bisnis"
        case .cnnIndonesia: return "CNN Indonesia Ekonomi"
        case .sec: return "SEC Filing"
        case .portfolio: return "Portofolio & P/L"
        case .other: return "News"
        }
    }

    var isIndonesian: Bool {
        switch self {
        case .kontan, .detikFinance, .liputan6, .tempo, .cnnIndonesia:
            return true
        default:
            return false
        }
    }

    var isUSGlobal: Bool {
        switch self {
        case .yahooFinance, .cnbc, .investing, .nasdaq, .globeNewswire, .prNewswire, .businessWire, .bloomberg, .reuters, .sec:
            return true
        default:
            return false
        }
    }

    var iconSystemName: String {
        switch self {
        case .yahooFinance: return "newspaper.fill"
        case .cnbc: return "chart.bar.xaxis"
        case .investing: return "chart.line.uptrend.xyaxis"
        case .nasdaq: return "chart.xyaxis.line"
        case .globeNewswire: return "newspaper"
        case .prNewswire: return "megaphone.fill"
        case .businessWire: return "doc.richtext"
        case .bloomberg: return "globe.americas.fill"
        case .reuters: return "antenna.radiowaves.left.and.right"
        case .kontan: return "newspaper.fill"
        case .detikFinance: return "banknote.fill"
        case .liputan6: return "flame.fill"
        case .tempo: return "book.fill"
        case .cnnIndonesia: return "globe.asia.australia.fill"
        case .sec: return "doc.text.fill"
        case .portfolio: return "briefcase.fill"
        case .other: return "link"
        }
    }

    var assetImageName: String {
        switch self {
        case .yahooFinance: return "logo_yahoo"
        case .cnbc: return "logo_cnbc"
        case .investing: return "logo_investing"
        case .nasdaq: return "logo_nasdaq"
        case .globeNewswire: return "logo_globenewswire"
        case .prNewswire: return "logo_prnewswire"
        case .businessWire: return "logo_businesswire"
        case .bloomberg: return "logo_bloomberg"
        case .reuters: return "logo_reuters"
        case .kontan: return "logo_kontan"
        case .detikFinance: return "logo_detik"
        case .liputan6: return "logo_liputan6"
        case .tempo: return "logo_tempo"
        case .cnnIndonesia: return "logo_cnn"
        case .sec: return "logo_sec"
        case .portfolio: return "logo_portfolio"
        case .other: return "logo_news"
        }
    }

    var shortBadge: String {
        switch self {
        case .yahooFinance: return "Y!"
        case .cnbc: return "CNBC"
        case .investing: return "INV"
        case .nasdaq: return "NDAQ"
        case .globeNewswire: return "GNW"
        case .prNewswire: return "PRN"
        case .businessWire: return "BW"
        case .bloomberg: return "BBG"
        case .reuters: return "R"
        case .kontan: return "KTN"
        case .detikFinance: return "DTK"
        case .liputan6: return "LP6"
        case .tempo: return "TMP"
        case .cnnIndonesia: return "CNN"
        case .sec: return "SEC"
        case .portfolio: return "P"
        case .other: return "N"
        }
    }

    var accentHex: String {
        switch self {
        case .yahooFinance: return "722EE5" // Purple
        case .cnbc: return "0D8CD9" // Blue
        case .investing: return "F7931A" // Orange
        case .nasdaq: return "0099CC" // Cyan / Nasdaq Blue
        case .globeNewswire: return "004F9F" // Deep Blue
        case .prNewswire: return "E04423" // Red/Orange
        case .businessWire: return "29539B" // Navy
        case .bloomberg: return "FF5933" // Orange
        case .reuters: return "FF8000" // Tangerine
        case .kontan: return "C41230" // Crimson Red (Kontan)
        case .detikFinance: return "002B7F" // Detik Blue
        case .liputan6: return "F26522" // Liputan6 Orange
        case .tempo: return "E51B24" // Tempo Red
        case .cnnIndonesia: return "CC0000" // CNN Red
        case .sec: return "EAA626" // Gold
        case .portfolio: return "00D084" // Emerald Green
        case .other: return "8E8E93" // Gray
        }
    }

    static func from(rawString: String) -> NewsSourceType {
        let lowered = rawString.lowercased()
        if lowered.contains("portfolio") || lowered.contains("portofolio") {
            return .portfolio
        } else if lowered.contains("sec") {
            return .sec
        } else if lowered.contains("kontan") {
            return .kontan
        } else if lowered.contains("detik") {
            return .detikFinance
        } else if lowered.contains("liputan6") {
            return .liputan6
        } else if lowered.contains("tempo") {
            return .tempo
        } else if lowered.contains("cnn indonesia") || (lowered.contains("cnn") && (lowered.contains("ekonomi") || lowered.contains("indonesia"))) {
            return .cnnIndonesia
        } else if lowered.contains("investing") {
            return .investing
        } else if lowered.contains("nasdaq") {
            return .nasdaq
        } else if lowered.contains("globenewswire") || lowered.contains("globe newswire") {
            return .globeNewswire
        } else if lowered.contains("prnewswire") || lowered.contains("pr newswire") {
            return .prNewswire
        } else if lowered.contains("businesswire") || lowered.contains("business wire") {
            return .businessWire
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
