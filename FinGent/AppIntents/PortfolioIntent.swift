// AppIntents/PortfolioIntent.swift

import AppIntents
import Foundation

// MARK: - IDX Stocks Enum

enum SahamIDX: String, AppEnum {
    case portfolio = "PORTFOLIO"
    case bbca = "BBCA"; case bbri = "BBRI"; case goto = "GOTO"
    case tlkm = "TLKM"; case bmri = "BMRI"; case asii = "ASII"
    case unvr = "UNVR"; case emtk = "EMTK"; case bren = "BREN"
    case ammn = "AMMN"; case aces = "ACES"; case icbp = "ICBP"

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Stock or Portfolio"
    static var caseDisplayRepresentations: [SahamIDX: DisplayRepresentation] = [
        .portfolio: DisplayRepresentation(
            title: "My Portfolio",
            subtitle: "All holdings in portfolio",
            synonyms: ["portfolio", "my portfolio", "portofolio", "all holdings", "holdings", "portfolio today", "portfolio today's", "saham saya", "holding saya"]
        ),
        .bbca: DisplayRepresentation(title: "BBCA", subtitle: "Bank Central Asia", synonyms: ["BCA", "Bank Central Asia", "B B C A"]),
        .bbri: DisplayRepresentation(title: "BBRI", subtitle: "Bank Rakyat Indonesia", synonyms: ["BRI", "Bank Rakyat Indonesia", "B B R I"]),
        .goto: DisplayRepresentation(title: "GOTO", subtitle: "GoTo Gojek Tokopedia", synonyms: ["GoTo", "Gojek", "Tokopedia", "G O T O"]),
        .tlkm: DisplayRepresentation(title: "TLKM", subtitle: "Telkom Indonesia", synonyms: ["Telkom", "T L K M"]),
        .bmri: DisplayRepresentation(title: "BMRI", subtitle: "Bank Mandiri", synonyms: ["Mandiri", "B M R I"]),
        .asii: DisplayRepresentation(title: "ASII", subtitle: "Astra International", synonyms: ["Astra", "A S I I"]),
        .unvr: DisplayRepresentation(title: "UNVR", subtitle: "Unilever Indonesia", synonyms: ["Unilever", "U N V R"]),
        .emtk: DisplayRepresentation(title: "EMTK", subtitle: "Elang Mahkota Teknologi", synonyms: ["Emtek", "E M T K"]),
        .bren: DisplayRepresentation(title: "BREN", subtitle: "Barito Renewables", synonyms: ["Barito", "B R E N"]),
        .ammn: DisplayRepresentation(title: "AMMN", subtitle: "Amman Mineral", synonyms: ["Amman", "A M M N"]),
        .aces: DisplayRepresentation(title: "ACES", subtitle: "Ace Hardware", synonyms: ["Ace Hardware", "A C E S"]),
        .icbp: DisplayRepresentation(title: "ICBP", subtitle: "Indofood CBP", synonyms: ["Indofood", "I C B P"])
    ]
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
        let isNewsQuery = q.contains("NEWS") || q.contains("BERITA")

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
            if let best = stockArticles.first(where: { $0.title.uppercased().contains(ticker) || $0.summary.uppercased().contains(ticker) }) ?? stockArticles.first {
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
        let aliases: [(String, String)] = [
            ("BANK CENTRAL ASIA", "BBCA"), ("BBCA", "BBCA"), ("BCA", "BBCA"),
            ("BANK RAKYAT INDONESIA", "BBRI"), ("BBRI", "BBRI"), ("BRI", "BBRI"),
            ("GOJEK TOKOPEDIA", "GOTO"), ("GOTO", "GOTO"), ("GOJEK", "GOTO"), ("TOKOPEDIA", "GOTO"),
            ("TELKOM INDONESIA", "TLKM"), ("TLKM", "TLKM"), ("TELKOM", "TLKM"),
            ("BANK MANDIRI", "BMRI"), ("BMRI", "BMRI"), ("MANDIRI", "BMRI"),
            ("ASTRA INTERNATIONAL", "ASII"), ("ASII", "ASII"), ("ASTRA", "ASII"),
            ("UNILEVER INDONESIA", "UNVR"), ("UNVR", "UNVR"), ("UNILEVER", "UNVR"),
            ("ELANG MAHKOTA", "EMTK"), ("EMTK", "EMTK"), ("EMTEK", "EMTK"),
            ("BARITO RENEWABLES", "BREN"), ("BREN", "BREN"), ("BARITO", "BREN"),
            ("AMMAN MINERAL", "AMMN"), ("AMMN", "AMMN"), ("AMMAN", "AMMN"),
            ("ACE HARDWARE", "ACES"), ("ACES", "ACES"),
            ("INDOFOOD CBP", "ICBP"), ("ICBP", "ICBP"), ("INDOFOOD", "ICBP")
        ]
        for (alias, ticker) in aliases where text.contains(alias) { return ticker }
        return nil
    }

    private func buildNewsReply(ticker: String, news: NewsRepositoryProtocol, market: MarketDataRepositoryProtocol) -> String {
        let articles = news.getArticles(for: [ticker])
        if let first = articles.first {
            return "Here is the latest news for \(ticker) from \(first.source): \(first.title). \(first.summary) Overall sentiment is \(first.sentiment.label)."
        }
        let price = market.getQuote(for: ticker)?.price ?? 0
        return "There are no major news headlines for \(ticker) today. The stock is currently trading at \(NumberFormatters.englishDecimal(price)) Rupiah."
    }

    private func buildStockReply(ticker: String, holdings: [UserHolding], market: MarketDataRepositoryProtocol) -> String {
        let quote = market.getQuote(for: ticker)
        let price = quote?.price ?? 0
        let priceText = NumberFormatters.englishDecimal(price)

        if let h = holdings.first(where: { $0.ticker.uppercased() == ticker }) {
            let pnl = h.pnl(at: price)
            let pnlPct = h.pnlPercent(at: price)
            let status = pnl >= 0 ? "profit" : "loss"
            let lotText = h.lots > 0 ? "\(h.lots) lots" : "\(h.shares) shares"
            return "You own \(lotText) of \(ticker). The current price is \(priceText) Rupiah. Total value is \(NumberFormatters.englishDecimal(h.currentValue(at: price))) Rupiah, with an unrealized \(status) of \(NumberFormatters.englishDecimal(abs(pnl))) Rupiah (\(String(format: "%+.1f", pnlPct))%)."
        }

        let changeText = quote.map { q in ", \(q.changePercent >= 0 ? "up" : "down") \(String(format: "%.1f", abs(q.changePercent)))% today" } ?? ""
        return "\(ticker) is at \(priceText) Rupiah today\(changeText). You don't have this stock in your FinGent portfolio yet."
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
        return "Your FinGent portfolio is currently valued at \(NumberFormatters.englishDecimal(totalValue)) Rupiah across \(holdings.count) stocks, with an overall \(status) of \(String(format: "%.1f", abs(pnlPct)))%."
    }
}

// MARK: - 2. CekPortfolioIntent

struct CekPortfolioIntent: AppIntent {
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
        let valText = NumberFormatters.englishDecimal(totalValue)
        let reply = "\(greeting)Your portfolio is valued at \(valText) Rupiah across \(holdings.count) stocks, currently showing a \(status) of \(String(format: "%.1f", abs(pnlPct)))%."
        return .result(dialog: IntentDialog(stringLiteral: reply))
    }
}

// MARK: - 3. CekSahamIntent

struct CekSahamIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Stock"
    static var description: IntentDescription = IntentDescription("Check the live price and holding details of a specific stock.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Stock", description: "The stock ticker symbol, such as BBCA, BBRI, or GOTO")
    var stock: SahamIDX

    static var parameterSummary: some ParameterSummary { Summary("Check \(\.$stock) in FinGent") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        if stock == .portfolio {
            let reply = checkPortfolioSummary()
            return .result(dialog: IntentDialog(stringLiteral: reply))
        }

        let ticker = stock.rawValue
        let market = MarketDataRepository.shared
        let holdings = PortfolioRepository.shared.userHoldings
        let quote = market.getQuote(for: ticker)
        let currentPrice = quote?.price ?? 0
        let priceText = NumberFormatters.englishDecimal(currentPrice)

        if let h = holdings.first(where: { $0.ticker.uppercased() == ticker }) {
            let pnl = h.pnl(at: currentPrice)
            let pnlPct = h.pnlPercent(at: currentPrice)
            let status = pnl >= 0 ? "profit" : "loss"
            let lotText = h.lots > 0 ? "\(h.lots) lots" : "\(h.shares) shares"
            let reply = "Your \(ticker) is at \(priceText) Rupiah today. You own \(lotText) worth \(NumberFormatters.englishDecimal(h.currentValue(at: currentPrice))) Rupiah, with an unrealized \(status) of \(NumberFormatters.englishDecimal(abs(pnl))) Rupiah (\(String(format: "%+.1f", pnlPct))%)."
            return .result(dialog: IntentDialog(stringLiteral: reply))
        }

        let changeText = quote.map { q in ", \(q.changePercent >= 0 ? "up" : "down") \(String(format: "%.1f", abs(q.changePercent)))% today" } ?? ""
        return .result(dialog: IntentDialog(stringLiteral: "\(ticker) is at \(priceText) Rupiah today\(changeText). You don't have this stock in your FinGent portfolio yet."))
    }

    private func checkPortfolioSummary() -> String {
        let repo = PortfolioRepository.shared
        let holdings = repo.userHoldings
        let market = MarketDataRepository.shared
        let userName = repo.userName
        let greeting = userName.isEmpty ? "" : "Hey \(userName)! "

        let effectiveHoldings: [UserHolding]
        if holdings.isEmpty {
            effectiveHoldings = [
                UserHolding(ticker: "BBCA", name: "Bank Central Asia", investedAmount: 10_000_000, pricePerShare: 10_125, sector: "Financials"),
                UserHolding(ticker: "TLKM", name: "Telkom Indonesia", investedAmount: 5_000_000, pricePerShare: 2_950, sector: "Technology")
            ]
        } else {
            effectiveHoldings = holdings
        }

        let resolved = effectiveHoldings.map { h -> StockHolding in
            let price = market.getQuote(for: h.ticker)?.price ?? h.pricePerShare
            return StockHolding(ticker: h.ticker, name: h.name, shares: h.shares, avgPrice: h.pricePerShare, currentPrice: price, sector: h.sector)
        }
        let totalValue = resolved.reduce(0) { $0 + $1.marketValue }
        let totalInvested = effectiveHoldings.reduce(0) { $0 + $1.investedAmount }
        let pnl = totalValue - totalInvested
        let pnlPct = totalInvested > 0 ? (pnl / totalInvested) * 100 : 0
        let status = pnl >= 0 ? "gain" : "loss"
        let valText = NumberFormatters.englishDecimal(totalValue)
        return "\(greeting)Your portfolio is valued at \(valText) Rupiah across \(effectiveHoldings.count) stocks, currently showing a \(status) of \(String(format: "%.1f", abs(pnlPct)))%."
    }
}

// MARK: - 4. CekBeritaIntent

struct CekBeritaIntent: AppIntent {
    static var title: LocalizedStringResource = "Check News"
    static var description: IntentDescription = IntentDescription("Check the latest news headlines for your portfolio or a specific stock.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Stock or Portfolio", description: "The stock ticker symbol or portfolio to check news for.")
    var stock: SahamIDX

    static var parameterSummary: some ParameterSummary { Summary("Check news for \(\.$stock) in FinGent") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        if stock == .portfolio {
            let reply = readPortfolioNews()
            return .result(dialog: IntentDialog(stringLiteral: reply))
        }

        let ticker = stock.rawValue
        let articles = NewsRepository.shared.getArticles(for: [ticker])
        if let first = articles.first {
            let reply = "Here is the latest news for \(ticker) from \(first.source): \(first.title). \(first.summary) Overall sentiment is \(first.sentiment.label)."
            return .result(dialog: IntentDialog(stringLiteral: reply))
        }
        let price = MarketDataRepository.shared.getQuote(for: ticker)?.price ?? 0
        let reply = "There are no breaking news stories for \(ticker) today. The stock is currently trading at \(NumberFormatters.englishDecimal(price)) Rupiah."
        return .result(dialog: IntentDialog(stringLiteral: reply))
    }

    private func readPortfolioNews() -> String {
        let holdings = PortfolioRepository.shared.userHoldings
        let tickers = holdings.isEmpty ? ["BBCA", "TLKM"] : holdings.map(\.ticker)
        let articles = NewsRepository.shared.getArticles(for: tickers)

        var newsSnippets: [String] = []
        for ticker in tickers {
            let stockArticles = articles.filter { $0.relatedTickers.contains(ticker) }
            if let best = stockArticles.first(where: { $0.title.uppercased().contains(ticker) || $0.summary.uppercased().contains(ticker) }) ?? stockArticles.first {
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

// MARK: - 5. CekBeritaPortfolioIntent

struct CekBeritaPortfolioIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Portfolio News"
    static var description: IntentDescription = IntentDescription("Check the latest news headlines for all stocks in your portfolio.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        var intent = CekBeritaIntent()
        intent.stock = .portfolio
        return try await intent.perform()
    }
}

