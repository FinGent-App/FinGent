// Core/Domain/Services/TickerExtractor.swift

import Foundation

// MARK: - TickerExtractor Protocol

protocol TickerExtractor: Sendable {
    func extractTickers(from article: NewsArticle) -> [String]
    func extractTickers(from text: String) -> [String]
}

// MARK: - StockTickerExtractor Implementation

final class StockTickerExtractor: TickerExtractor {

    // MARK: - Known Alias Dictionary (Company Name / Keyword -> Ticker)

    private let companyAliases: [String: String] = [
        // US Tech / Semis / Global Market Leaders
        "micron": "MU",
        "micron technology": "MU",
        "nvidia": "NVDA",
        "nvidia corp": "NVDA",
        "advanced micro devices": "AMD",
        "amd": "AMD",
        "broadcom": "AVGO",
        "taiwan semiconductor": "TSM",
        "tsmc": "TSM",
        "apple": "AAPL",
        "apple inc": "AAPL",
        "microsoft": "MSFT",
        "google": "GOOGL",
        "alphabet": "GOOGL",
        "amazon": "AMZN",
        "meta": "META",
        "meta platforms": "META",
        "facebook": "META",
        "tesla": "TSLA",
        "intel": "INTC",
        "qualcomm": "QCOM",
        "arm holdings": "ARM",
        "arm": "ARM",
        "super micro": "SMCI",
        "supermicro": "SMCI",
        "palantir": "PLTR",
        "netflix": "NFLX",
        "coinbase": "COIN",
        "oracle": "ORCL",
        "salesforce": "CRM",
        "uber": "UBER",
        "alibaba": "BABA"
    ]

    // MARK: - Known Tickers Set

    private let knownTickers: Set<String>

    // Common words that could collide with 1-2 letter tickers
    private let blacklistWords: Set<String> = [
        "A", "I", "IN", "ON", "AN", "AT", "BY", "FOR", "IF", "IS", "IT", "OF",
        "OR", "TO", "UP", "US", "BE", "DO", "GO", "HE", "ME", "MY", "NO", "SO", "WE",
        "ALL", "ARE", "AND", "CAN", "OUT", "NEW", "NOW", "ONE", "SEE", "BUY", "PAY",
        "KEY", "TOP", "BIG", "CEO", "CFO", "CTO", "GDP", "CPI", "FED", "SEC", "IPO", "ETF"
    ]

    // MARK: - Initializer

    nonisolated init(additionalTickers: Set<String> = []) {
        var base: Set<String> = [
            "NVDA", "MU", "AMD", "AVGO", "TSM", "AAPL", "MSFT", "GOOGL", "GOOG",
            "AMZN", "META", "TSLA", "INTC", "QCOM", "ARM", "SMCI", "PLTR", "NFLX",
            "COIN", "ORCL", "CRM", "UBER", "BABA"
        ]
        base.formUnion(additionalTickers.map { $0.uppercased() })
        self.knownTickers = base
    }

    // MARK: - Extraction Methods

    func extractTickers(from article: NewsArticle) -> [String] {
        let combined = "\(article.title) \(article.summary ?? "")"
        return extractTickers(from: combined)
    }

    func extractTickers(from text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var detected = Set<String>()

        // 1. Company Aliases Matching
        let lowered = text.lowercased()
        for (company, ticker) in companyAliases {
            // Check as whole word or phrase boundary
            if containsWord(in: lowered, word: company) {
                detected.insert(ticker)
            }
        }

        // 2. Explicit Stock Symbols (e.g. $MU, (NASDAQ:NVDA), (NYSE:TSLA), (MU))
        let symbolPattern = #"(?:[\$]|(?:\((?:NASDAQ|NYSE|AMEX|IDX):)|(?:\())(\b[A-Z]{1,5}\b)(?:\))?"#
        if let regex = try? NSRegularExpression(pattern: symbolPattern, options: [.caseInsensitive]) {
            let nsText = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                if match.numberOfRanges > 1 {
                    let symbol = nsText.substring(with: match.range(at: 1)).uppercased()
                    if !blacklistWords.contains(symbol) {
                        detected.insert(symbol)
                    }
                }
            }
        }

        // 3. Isolated Ticker Words with Word Boundaries
        let tokens = text.components(separatedBy: CharacterSet.alphanumerics.inverted)
        for token in tokens where !token.isEmpty {
            let upper = token.uppercased()
            if knownTickers.contains(upper) && !blacklistWords.contains(upper) {
                // Ensure it was capitalized in original text (e.g. "MU" not "mu")
                if token == upper || token.count >= 3 {
                    detected.insert(upper)
                }
            }
        }

        return Array(detected).sorted()
    }

    // MARK: - Helper

    private func containsWord(in text: String, word: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: #"\b"# + NSRegularExpression.escapedPattern(for: word) + #"\b"#, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.firstMatch(in: text, range: range) != nil
    }
}
