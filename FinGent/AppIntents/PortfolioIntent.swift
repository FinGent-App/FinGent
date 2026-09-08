// AppIntents/PortfolioIntent.swift

import AppIntents
import Foundation

// MARK: - General Stock Enum

enum StockChoice: String, AppEnum {
    case portfolio = "PORTFOLIO"
    case aapl = "AAPL"
    case nvda = "NVDA"
    case msft = "MSFT"
    case goog = "GOOGL"
    case amzn = "AMZN"
    case meta = "META"
    case tsla = "TSLA"
    case mu = "MU"
    case spy = "SPY"

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Stock or Portfolio"
    static var caseDisplayRepresentations: [StockChoice: DisplayRepresentation] = [
        .portfolio: DisplayRepresentation(
            title: "My Portfolio",
            subtitle: "All holdings in portfolio",
            synonyms: ["portfolio", "my portfolio", "all holdings", "holdings", "my stocks", "portfolio today", "portfolio summary"]
        ),
        .aapl: DisplayRepresentation(title: "AAPL", subtitle: "Apple Inc.", synonyms: ["Apple", "A A P L"]),
        .nvda: DisplayRepresentation(title: "NVDA", subtitle: "NVIDIA Corp.", synonyms: ["Nvidia", "N V D A"]),
        .msft: DisplayRepresentation(title: "MSFT", subtitle: "Microsoft Corp.", synonyms: ["Microsoft", "M S F T"]),
        .goog: DisplayRepresentation(title: "GOOGL", subtitle: "Alphabet Inc.", synonyms: ["Google", "Alphabet", "G O O G L"]),
        .amzn: DisplayRepresentation(title: "AMZN", subtitle: "Amazon.com Inc.", synonyms: ["Amazon", "A M Z N"]),
        .meta: DisplayRepresentation(title: "META", subtitle: "Meta Platforms", synonyms: ["Meta", "Facebook", "M E T A"]),
        .tsla: DisplayRepresentation(title: "TSLA", subtitle: "Tesla Inc.", synonyms: ["Tesla", "T S L A"]),
        .mu: DisplayRepresentation(title: "MU", subtitle: "Micron Technology", synonyms: ["Micron", "M U"]),
        .spy: DisplayRepresentation(title: "SPY", subtitle: "SPDR S&P 500 ETF", synonyms: ["S&P 500", "S P Y"])
    ]
}

// Backward compatibility alias
typealias SahamIDX = StockChoice

// MARK: - Currency Formatting Helper

fileprivate func formatCurrency(value: Double, ticker: String) -> String {
    let quote = MarketDataRepository.shared.getQuote(for: ticker)
    let isUSD = quote?.isUSD ?? (quote?.currency.uppercased() == "USD" || !ticker.hasSuffix(".JK"))
    if isUSD {
        return String(format: "$%.2f", value)
    } else {
        return "Rp " + NumberFormatters.englishDecimal(value)
    }
}

// MARK: - 1. AskFinGentIntent

struct AskFinGentIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask FinGent AI"
    static var description: IntentDescription = IntentDescription("Ask FinGent AI any question about your stock portfolio, market prices, or financial news.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Question", requestValueDialog: IntentDialog("What would you like to ask FinGent?"))
    var question: String

    static var parameterSummary: some ParameterSummary { Summary("Ask FinGent \(\.$question)") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let agent = await FinGentAgent()
        do {
            let answer = try await agent.ask(question)
            return .result(dialog: IntentDialog(stringLiteral: answer))
        } catch {
            return .result(dialog: IntentDialog(stringLiteral: buildFallbackReply(for: question)))
        }
    }

    private func buildFallbackReply(for question: String) -> String {
        let q = question.uppercased()
        let holdings = PortfolioRepository.shared.userHoldings
        let market = MarketDataRepository.shared
        let news = NewsRepository.shared
        let isNewsQuery = q.contains("NEWS")

        if let ticker = matchTicker(in: q) {
            if isNewsQuery {
                return buildNewsReply(ticker: ticker, news: news, market: market)
            }
            return buildStockReply(ticker: ticker, holdings: holdings, market: market)
        }

        if isNewsQuery || (q.contains("PORTFOLIO") && (isNewsQuery || q.contains("UPDATE"))) {
            return buildPortfolioNewsReply(holdings: holdings, news: news)
        }

        return buildPortfolioSummaryReply(holdings: holdings)
    }

    private func buildPortfolioNewsReply(holdings: [UserHolding], news: NewsRepositoryProtocol) -> String {
        guard !holdings.isEmpty else {
            return "Your portfolio is currently empty. Please open FinGent to add your stocks first."
        }
        let tickers = holdings.map(\.ticker)
        let articles = news.getArticles(for: tickers)
        guard !articles.isEmpty else {
            let tickerList = tickers.joined(separator: " and ")
            return "There are no major news headlines for \(tickerList) today."
        }

        var newsSnippets: [String] = []
        for ticker in tickers {
            let stockArticles = articles.filter { $0.relatedTickers.contains(ticker) }
            if let best = stockArticles.first(where: { $0.title.uppercased().contains(ticker) || ($0.summary?.uppercased().contains(ticker) ?? false) }) ?? stockArticles.first {
                newsSnippets.append("For \(ticker), \(best.title)")
            }
        }

        if newsSnippets.isEmpty {
            let tickerList = tickers.joined(separator: " and ")
            return "There are no major news headlines for \(tickerList) today."
        }
        return "Here is the latest news for your holdings: " + newsSnippets.joined(separator: ". ") + "."
    }

    private func matchTicker(in text: String) -> String? {
        let holdings = PortfolioRepository.shared.userHoldings

        // 1. Dynamic match from user's current holdings (ticker or company name)
        for h in holdings {
            if text.contains(h.ticker.uppercased()) || text.contains(h.name.uppercased()) {
                return h.ticker.uppercased()
            }
        }

        // 2. Common general stock aliases
        let generalAliases: [(String, String)] = [
            ("APPLE", "AAPL"), ("AAPL", "AAPL"),
            ("NVIDIA", "NVDA"), ("NVDA", "NVDA"),
            ("MICROSOFT", "MSFT"), ("MSFT", "MSFT"),
            ("GOOGLE", "GOOGL"), ("ALPHABET", "GOOGL"), ("GOOGL", "GOOGL"), ("GOOG", "GOOGL"),
            ("AMAZON", "AMZN"), ("AMZN", "AMZN"),
            ("META", "META"), ("FACEBOOK", "META"),
            ("TESLA", "TSLA"), ("TSLA", "TSLA"),
            ("MICRON", "MU"), ("MU", "MU"),
            ("AMD", "AMD"), ("ADVANCED MICRO", "AMD"),
            ("INTEL", "INTC"), ("INTC", "INTC"),
            ("NETFLIX", "NFLX"), ("NFLX", "NFLX"),
            ("S&P 500", "SPY"), ("SPDR", "SPY"), ("SPY", "SPY")
        ]
        for (alias, ticker) in generalAliases where text.contains(alias) {
            return ticker
        }

        // 3. Dynamic token check against marketRepo
        let words = text.components(separatedBy: CharacterSet.alphanumerics.inverted)
        for word in words {
            let w = word.trimmingCharacters(in: .whitespaces).uppercased()
            if w.count >= 2 && w.count <= 5 && !["THE", "FOR", "HOW", "ABOUT", "WHAT", "NEWS", "STOCK", "TODAY", "PRICE", "CHECK", "SHOW"].contains(w) {
                if MarketDataRepository.shared.getQuote(for: w) != nil {
                    return w
                }
            }
        }
        return nil
    }

    private func buildNewsReply(ticker: String, news: NewsRepositoryProtocol, market: MarketDataRepositoryProtocol) -> String {
        let articles = news.getArticles(for: [ticker])
        if let first = articles.first {
            return "Here is the latest news for \(ticker) from \(first.source): \(first.title). \(first.summary) Overall sentiment is \(first.sentiment.label)."
        }
        let price = market.getQuote(for: ticker)?.price ?? 0
        let priceText = formatCurrency(value: price, ticker: ticker)
        return "There are no major news headlines for \(ticker) today. The stock is currently trading at \(priceText)."
    }

    private func buildStockReply(ticker: String, holdings: [UserHolding], market: MarketDataRepositoryProtocol) -> String {
        let quote = market.getQuote(for: ticker)
        let price = quote?.price ?? 0
        let priceText = formatCurrency(value: price, ticker: ticker)

        if let h = holdings.first(where: { $0.ticker.uppercased() == ticker }) {
            let pnl = h.pnl(at: price)
            let pnlPct = h.pnlPercent(at: price)
            let status = pnl >= 0 ? "profit" : "loss"
            let sharesText = "\(h.shares) shares"
            let valueText = formatCurrency(value: h.currentValue(at: price), ticker: ticker)
            let pnlText = formatCurrency(value: abs(pnl), ticker: ticker)
            return "You own \(sharesText) of \(ticker). The current price is \(priceText). Total value is \(valueText), with an unrealized \(status) of \(pnlText) (\(String(format: "%+.1f", pnlPct))%)."
        }

        let changeText = quote.map { q in ", \(q.changePercent >= 0 ? "up" : "down") \(String(format: "%.1f", abs(q.changePercent)))% today" } ?? ""
        return "\(ticker) is currently trading at \(priceText)\(changeText). You do not have this stock in your FinGent portfolio."
    }

    private func buildPortfolioSummaryReply(holdings: [UserHolding]) -> String {
        guard !holdings.isEmpty else {
            return "Your FinGent portfolio is currently empty. Please open the app to add your first stock."
        }
        let market = MarketDataRepository.shared
        let resolved = holdings.map { h -> StockHolding in
            let price = market.getQuote(for: h.ticker)?.price ?? h.pricePerShare
            return StockHolding(ticker: h.ticker, name: h.name, shares: h.shares, avgPrice: h.pricePerShare, currentPrice: price, sector: h.sector)
        }
        let totalValue = resolved.reduce(0) { $0 + $1.marketValue }
        let totalInvested = holdings.reduce(0) { $0 + $1.investedAmount }
        let pnl = totalValue - totalInvested
        let pnlPct = totalInvested > 0 ? (pnl / totalInvested) * 100 : 0
        let status = pnl >= 0 ? "profit" : "loss"
        let isAllUSD = holdings.allSatisfy { $0.isUSD }
        let totalValueText = isAllUSD ? String(format: "$%.2f", totalValue) : "$" + NumberFormatters.englishDecimal(totalValue)
        return "Your FinGent portfolio is currently valued at \(totalValueText) across \(holdings.count) stocks, with an overall \(status) of \(String(format: "%.1f", abs(pnlPct)))%."
    }
}

// MARK: - 2. CheckPortfolioIntent

struct CheckPortfolioIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Portfolio"
    static var description: IntentDescription = IntentDescription("Check your overall portfolio value and performance today.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let repo = PortfolioRepository.shared
        let holdings = repo.userHoldings
        let market = MarketDataRepository.shared
        let userName = repo.userName
        let greeting = userName.isEmpty ? "" : "Hey \(userName)! "

        guard !holdings.isEmpty else {
            return .result(dialog: IntentDialog(stringLiteral: "\(greeting)Your portfolio is currently empty. Please open FinGent to add stocks."))
        }

        let resolved = holdings.map { h -> StockHolding in
            let price = market.getQuote(for: h.ticker)?.price ?? h.pricePerShare
            return StockHolding(ticker: h.ticker, name: h.name, shares: h.shares, avgPrice: h.pricePerShare, currentPrice: price, sector: h.sector)
        }
        let totalValue = resolved.reduce(0) { $0 + $1.marketValue }
        let totalInvested = holdings.reduce(0) { $0 + $1.investedAmount }
        let pnl = totalValue - totalInvested
        let pnlPct = totalInvested > 0 ? (pnl / totalInvested) * 100 : 0
        let status = pnl >= 0 ? "gain" : "loss"
        let isAllUSD = holdings.allSatisfy { $0.isUSD }
        let valText = isAllUSD ? String(format: "$%.2f", totalValue) : "$" + NumberFormatters.englishDecimal(totalValue)
        let reply = "\(greeting)Your portfolio is valued at \(valText) across \(holdings.count) stocks, currently showing a \(status) of \(String(format: "%.1f", abs(pnlPct)))%."
        return .result(dialog: IntentDialog(stringLiteral: reply))
    }
}

// MARK: - 3. CheckStockIntent

struct CheckStockIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Stock"
    static var description: IntentDescription = IntentDescription("Check the live price and holding details of a specific stock.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Stock", description: "The stock ticker symbol or portfolio.")
    var stock: StockChoice

    @Parameter(title: "Custom Ticker", description: "Optional custom stock ticker symbol, e.g. AMD, INTC, or AAPL.")
    var customTicker: String?

    static var parameterSummary: some ParameterSummary { Summary("Check \(\.$stock) in FinGent") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ticker: String
        if let custom = customTicker?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            ticker = custom.uppercased()
        } else if stock == .portfolio {
            let reply = checkPortfolioSummary()
            return .result(dialog: IntentDialog(stringLiteral: reply))
        } else {
            ticker = stock.rawValue
        }

        let market = MarketDataRepository.shared
        let holdings = PortfolioRepository.shared.userHoldings
        let quote = market.getQuote(for: ticker)
        let currentPrice = quote?.price ?? 0
        let priceText = formatCurrency(value: currentPrice, ticker: ticker)

        if let h = holdings.first(where: { $0.ticker.uppercased() == ticker }) {
            let pnl = h.pnl(at: currentPrice)
            let pnlPct = h.pnlPercent(at: currentPrice)
            let status = pnl >= 0 ? "profit" : "loss"
            let sharesText = "\(h.shares) shares"
            let valueText = formatCurrency(value: h.currentValue(at: currentPrice), ticker: ticker)
            let pnlText = formatCurrency(value: abs(pnl), ticker: ticker)
            let reply = "Your \(ticker) is at \(priceText) today. You own \(sharesText) worth \(valueText), with an unrealized \(status) of \(pnlText) (\(String(format: "%+.1f", pnlPct))%)."
            return .result(dialog: IntentDialog(stringLiteral: reply))
        }

        let changeText = quote.map { q in ", \(q.changePercent >= 0 ? "up" : "down") \(String(format: "%.1f", abs(q.changePercent)))% today" } ?? ""
        return .result(dialog: IntentDialog(stringLiteral: "\(ticker) is at \(priceText) today\(changeText). You do not have this stock in your FinGent portfolio."))
    }

    private func checkPortfolioSummary() -> String {
        let repo = PortfolioRepository.shared
        let holdings = repo.userHoldings
        let market = MarketDataRepository.shared
        let userName = repo.userName
        let greeting = userName.isEmpty ? "" : "Hey \(userName)! "

        guard !holdings.isEmpty else {
            return "\(greeting)Your portfolio is currently empty. Please open FinGent to add your stocks."
        }

        let resolved = holdings.map { h -> StockHolding in
            let price = market.getQuote(for: h.ticker)?.price ?? h.pricePerShare
            return StockHolding(ticker: h.ticker, name: h.name, shares: h.shares, avgPrice: h.pricePerShare, currentPrice: price, sector: h.sector)
        }
        let totalValue = resolved.reduce(0) { $0 + $1.marketValue }
        let totalInvested = holdings.reduce(0) { $0 + $1.investedAmount }
        let pnl = totalValue - totalInvested
        let pnlPct = totalInvested > 0 ? (pnl / totalInvested) * 100 : 0
        let status = pnl >= 0 ? "gain" : "loss"
        let isAllUSD = holdings.allSatisfy { $0.isUSD }
        let valText = isAllUSD ? String(format: "$%.2f", totalValue) : "$" + NumberFormatters.englishDecimal(totalValue)
        return "\(greeting)Your portfolio is valued at \(valText) across \(holdings.count) stocks, currently showing a \(status) of \(String(format: "%.1f", abs(pnlPct)))%."
    }
}

// MARK: - 4. CheckNewsIntent

struct CheckNewsIntent: AppIntent {
    static var title: LocalizedStringResource = "Check News"
    static var description: IntentDescription = IntentDescription("Check the latest news headlines for your portfolio or a specific stock.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Stock or Portfolio", description: "The stock ticker symbol or portfolio to check news for.")
    var stock: StockChoice

    @Parameter(title: "Custom Ticker", description: "Optional custom stock ticker symbol, e.g. AMD, INTC, or AAPL.")
    var customTicker: String?

    static var parameterSummary: some ParameterSummary { Summary("Check news for \(\.$stock) in FinGent") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ticker: String
        if let custom = customTicker?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            ticker = custom.uppercased()
        } else if stock == .portfolio {
            let reply = readPortfolioNews()
            return .result(dialog: IntentDialog(stringLiteral: reply))
        } else {
            ticker = stock.rawValue
        }

        let articles = NewsRepository.shared.getArticles(for: [ticker])
        if let first = articles.first {
            let reply = "Here is the latest news for \(ticker) from \(first.source): \(first.title). \(first.summary) Overall sentiment is \(first.sentiment.label)."
            return .result(dialog: IntentDialog(stringLiteral: reply))
        }
        let price = MarketDataRepository.shared.getQuote(for: ticker)?.price ?? 0
        let priceText = formatCurrency(value: price, ticker: ticker)
        let reply = "There are no breaking news stories for \(ticker) today. The stock is currently trading at \(priceText)."
        return .result(dialog: IntentDialog(stringLiteral: reply))
    }

    private func readPortfolioNews() -> String {
        let holdings = PortfolioRepository.shared.userHoldings
        guard !holdings.isEmpty else {
            return "Your portfolio is currently empty. Please add stocks in FinGent to receive personalized news updates."
        }
        let tickers = holdings.map(\.ticker)
        let articles = NewsRepository.shared.getArticles(for: tickers)

        var newsSnippets: [String] = []
        for ticker in tickers {
            let stockArticles = articles.filter { $0.relatedTickers.contains(ticker) }
            if let best = stockArticles.first(where: { $0.title.uppercased().contains(ticker) || ($0.summary?.uppercased().contains(ticker) ?? false) }) ?? stockArticles.first {
                newsSnippets.append("For \(ticker), \(best.title)")
            }
        }

        if newsSnippets.isEmpty {
            let tickerList = tickers.joined(separator: " and ")
            return "There are no breaking news stories today for your portfolio holdings (\(tickerList))."
        } else {
            return "Here is the latest news for your holdings: " + newsSnippets.joined(separator: ". ") + "."
        }
    }
}

// MARK: - 5. CheckPortfolioNewsIntent

struct CheckPortfolioNewsIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Portfolio News"
    static var description: IntentDescription = IntentDescription("Check the latest news headlines for all stocks in your portfolio.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        var intent = CheckNewsIntent()
        intent.stock = .portfolio
        return try await intent.perform()
    }
}

// MARK: - Backward Compatibility Aliases

typealias CekPortfolioIntent = CheckPortfolioIntent
typealias CekSahamIntent = CheckStockIntent
typealias CekBeritaIntent = CheckNewsIntent
typealias CekBeritaPortfolioIntent = CheckPortfolioNewsIntent
