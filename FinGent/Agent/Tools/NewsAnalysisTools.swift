// Agent/Tools/NewsAnalysisTools.swift

import Foundation
import FoundationModels

// MARK: - 1. GetLatestNews

struct GetLatestNewsTool: Tool {
    let name = "getLatestNews"
    let description = "Gets the latest market and financial news articles. Specify the number of articles to retrieve (1–10)."

    @Generable struct Arguments {
        @Guide(description: "Number of news articles to return, between 1 and 10.", .range(1...10))
        var count: Int
    }

    func call(arguments: Arguments) async throws -> String {
        let articles = Array(NewsRepository.shared.allArticles.prefix(arguments.count))
        return formatArticles(articles, header: "Latest Market News (\(articles.count) articles):")
    }
}

// MARK: - 2. SearchMarketNews

struct SearchMarketNewsTool: Tool {
    let name = "searchMarketNews" // id
    let description = "Searches for market news articles by keyword, topic, or stock ticker."

    @Generable struct Arguments {
        @Guide(description: "Search keyword or topic, e.g. 'interest rate', 'BBCA', 'GDP'.")
        var query: String
    }

    func call(arguments: Arguments) async throws -> String {
        let results = NewsRepository.shared.searchArticles(query: arguments.query)
        guard !results.isEmpty else {
            return "No news articles found matching '\(arguments.query)'. Try different keywords."
        }
        return formatArticles(results, header: "News Search Results for '\(arguments.query)' (\(results.count) found):")
    }
}

// MARK: - 3. GetPortfolioNews

struct GetPortfolioNewsTool: Tool {
    let name = "getPortfolioNews"
    let description = "Gets news articles relevant to the user's stock holdings. Pass a specific ticker or leave empty for all holdings."

    @Generable struct Arguments {
        @Guide(description: "Specific stock ticker, e.g. 'BBCA'. Leave empty or pass 'ALL' for all holdings.")
        var ticker: String
    }

    func call(arguments: Arguments) async throws -> String {
        let cleanTicker = arguments.ticker.trimmingCharacters(in: .whitespaces).uppercased()
        let targetTickers: [String]

        if !cleanTicker.isEmpty && cleanTicker != "ALL" {
            targetTickers = [cleanTicker]
        } else {
            let holdings = await MainActor.run { PortfolioRepository.shared.userHoldings }
            targetTickers = holdings.isEmpty ? ["BBCA", "BBRI", "TLKM", "GOTO", "BMRI"] : holdings.map(\.ticker)
        }

        let articles = NewsRepository.shared.getArticles(for: targetTickers)
        guard !articles.isEmpty else {
            let target = cleanTicker.isEmpty || cleanTicker == "ALL" ? "your portfolio" : cleanTicker
            return "No recent news found related to \(target)."
        }

        let header = cleanTicker.isEmpty || cleanTicker == "ALL"
            ? "News Related to Your Portfolio (\(articles.count) articles):"
            : "Latest News for \(cleanTicker) (\(articles.count) articles):"

        return formatArticles(articles, header: header)
    }
}

// MARK: - 4. AnalyzeNewsImpact

struct AnalyzeNewsImpactTool: Tool {
    let name = "analyzeNewsImpact"
    let description = "Analyzes the potential impact of a news headline or topic on related stocks."

    @Generable struct Arguments {
        @Guide(description: "The news headline or topic to analyze.")
        var newsTitle: String
    }

    func call(arguments: Arguments) async throws -> String {
        let matching = NewsRepository.shared.searchArticles(query: arguments.newsTitle)

        guard let article = matching.first else {
            return """
            News Impact Analysis:

            📰 Topic: \(arguments.newsTitle)
            ⚠️ No matching news article found in database.
            """
        }

        var result = """
        News Impact Analysis:

        📰 News: \(article.title)
        📊 Sentiment: \(article.sentiment.rawValue.uppercased())
        📅 Date: \(article.date)

        Affected Stocks:
        """
        for ticker in article.relatedTickers {
            if let quote = MarketDataRepository.shared.getQuote(for: ticker) {
                let emoji = quote.changePercent >= 0 ? "📈" : "📉"
                result += "\n- \(ticker) (\(quote.name)): Rp \(formatNumber(quote.price)) (\(String(format: "%+.2f", quote.changePercent))%) \(emoji)"
            }
        }
        result += "\n\nImpact Summary: \(article.summary)"
        return result
    }
}

// MARK: - 5. AnalyzePortfolioImpact

struct AnalyzePortfolioImpactTool: Tool {
    let name = "analyzePortfolioImpact"
    let description = "Analyzes how a specific market event or scenario could impact the user's portfolio."

    @Generable struct Arguments {
        @Guide(description: "The market event or scenario to analyze, e.g. 'interest rate hike', 'rupiah depreciation'.")
        var event: String
    }

    func call(arguments: Arguments) async throws -> String {
        let userHoldings = await MainActor.run { PortfolioRepository.shared.userHoldings }
        guard !userHoldings.isEmpty else {
            return "Portofolio kamu saat ini masih kosong."
        }

        let holdings = userHoldings.map { h -> StockHolding in
            let price = MarketDataRepository.shared.getQuote(for: h.ticker)?.price ?? h.pricePerShare
            return StockHolding(ticker: h.ticker, name: h.name, shares: h.shares, avgPrice: h.pricePerShare, currentPrice: price, sector: h.sector)
        }

        let totalValue = holdings.reduce(0) { $0 + $1.marketValue }
        let event = arguments.event.lowercased()
        let affected = affectedHoldings(event: event, holdings: holdings)
        let affectedValue = affected.reduce(0) { $0 + $1.0.marketValue }
        let exposurePct = (affectedValue / totalValue) * 100

        var result = """
        Portfolio Impact Analysis:

        🎯 Event: \(arguments.event)
        💰 Portfolio Value: Rp \(formatNumber(totalValue))
        ⚡ Exposure: Rp \(formatNumber(affectedValue)) (\(String(format: "%.1f", exposurePct))% of portfolio)

        Affected Holdings:
        """
        for (h, reason) in affected {
            let weight = (h.marketValue / totalValue) * 100
            result += "\n- \(h.ticker) (\(h.name)): Rp \(formatNumber(h.marketValue)) (\(String(format: "%.1f", weight))%)"
            result += "\n  Reason: \(reason)"
        }
        result += "\n\nNote: Data-driven exposure analysis. The AI model will provide deeper qualitative analysis."
        return result
    }

    private func affectedHoldings(event: String, holdings: [StockHolding]) -> [(StockHolding, String)] {
        if event.contains("interest rate") || event.contains("suku bunga") {
            return holdings.filter { $0.sector == "Financials" }.map { ($0, "Banking sector directly impacted by interest rate changes") }
        }
        if event.contains("rupiah") || event.contains("currency") || event.contains("dollar") {
            return holdings.map { ($0, "Currency fluctuation impacts all stocks") }
        }
        if event.contains("tech") || event.contains("teknologi") {
            return holdings.filter { $0.sector == "Technology" }.map { ($0, "Technology sector directly impacted") }
        }
        if event.contains("consumer") || event.contains("konsumen") {
            return holdings.filter { $0.sector.contains("Consumer") }.map { ($0, "Consumer sector directly impacted") }
        }
        if event.contains("inflation") || event.contains("inflasi") {
            return holdings.map { ($0, "Inflation impacts all sectors differently") }
        }
        let direct = holdings.compactMap { h -> (StockHolding, String)? in
            (event.contains(h.ticker.lowercased()) || event.contains(h.name.lowercased()))
                ? (h, "Directly mentioned in event") : nil
        }
        return direct.isEmpty ? holdings.map { ($0, "General market impact") } : direct
    }
}

// MARK: - Shared Helpers

private func formatArticles(_ articles: [NewsArticle], header: String) -> String {
    var result = "\(header)\n"
    for (i, article) in articles.enumerated() {
        result += """
        \n\(i + 1). \(article.sentiment.emoji) \(article.title)
           Source: \(article.source) | Date: \(article.date)
           Summary: \(article.summary)
           Related: \(article.relatedTickers.joined(separator: ", "))
        """
    }
    return result
}

nonisolated private func formatNumber(_ value: Double) -> String {
    NumberFormatters.stockPrice(value)
}
