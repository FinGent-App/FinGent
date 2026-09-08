// Core/Data/Repository/MarketDataRepository.swift

import Foundation
import Observation

@Observable
final class MarketDataRepository: MarketDataRepositoryProtocol, @unchecked Sendable {

    static let shared = MarketDataRepository()

    // MARK: - Observable State

    private(set) var quotes: [String: StockQuote] = [:]
    private(set) var priceDirections: [String: PriceDirection] = [:]
    private(set) var lastTick: Date = Date()

    private var simulationTimer: Timer?

    // MARK: - Init

    private init() {
        self.quotes = Self.makeInitialQuotes()
        for ticker in quotes.keys {
            priceDirections[ticker] = .unchanged
        }
        startRealtimeSimulation()
        Task { [weak self] in
            await self?.refreshFromBackend()
        }
    }

    // MARK: - MarketDataRepositoryProtocol

    func getQuote(for ticker: String) -> StockQuote? {
        quotes[ticker.uppercased()]
    }

    func getFundamentals(for ticker: String) -> StockFundamentals? {
        Self.fundamentalsData[ticker.uppercased()]
    }

    func getPerformance(for ticker: String) -> StockPerformance? {
        let upper = ticker.uppercased()
        guard let p = Self.performanceData[upper], let q = getQuote(for: upper) else { return nil }
        return StockPerformance(
            ticker: q.ticker,
            name: q.name,
            daily: q.changePercent,
            weekly: p.weekly,
            monthly: p.monthly,
            ytd: p.ytd,
            yearly: p.yearly,
            threeMonth: p.threeMonth,
            fiveYear: p.fiveYear
        )
    }

    var topGainers: [MarketMover] {
        quotes.values
            .sorted { $0.changePercent > $1.changePercent }
            .prefix(5)
            .map { MarketMover(ticker: $0.ticker, name: $0.name, price: $0.price, changePercent: $0.changePercent) }
    }

    var topLosers: [MarketMover] {
        quotes.values
            .sorted { $0.changePercent < $1.changePercent }
            .prefix(5)
            .map { MarketMover(ticker: $0.ticker, name: $0.name, price: $0.price, changePercent: $0.changePercent) }
    }

    var mostActive: [MarketMover] {
        quotes.values
            .sorted { $0.volume > $1.volume }
            .prefix(5)
            .map { MarketMover(ticker: $0.ticker, name: $0.name, price: $0.price, changePercent: $0.changePercent) }
    }

    // MARK: - Simulation

    func startRealtimeSimulation() {
        guard simulationTimer == nil else { return }
        simulationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.simulateMarketTick()
            }
        }
    }

    func stopRealtimeSimulation() {
        simulationTimer?.invalidate()
        simulationTimer = nil
    }

    // MARK: - Backend Sync

    @MainActor
    func refreshFromBackend() async {
        let tickers = Array(quotes.keys)
        guard !tickers.isEmpty else { return }
        do {
            let liveQuotes = try await StockApiClient.shared.fetchBatch(tickers: tickers)
            for q in liveQuotes {
                let oldPrice = quotes[q.ticker]?.price ?? q.price
                let dir: PriceDirection = q.price > oldPrice ? .up : (q.price < oldPrice ? .down : .unchanged)
                self.quotes[q.ticker] = q
                self.priceDirections[q.ticker] = dir
            }
            self.lastTick = Date()
        } catch {
            // Silently retain current quotes if backend is momentarily unreachable
        }
    }

    @MainActor
    func registerRemoteQuote(_ quote: StockQuote, fundamentals: StockFundamentals? = nil) {
        self.quotes[quote.ticker] = quote
        self.priceDirections[quote.ticker] = .unchanged
        if let f = fundamentals {
            Self.fundamentalsData[quote.ticker] = f
        }
        self.lastTick = Date()
    }

    @MainActor
    func registerRemoteHoldingMarketData(
        ticker: String,
        name: String,
        price: Double,
        currency: String = "IDR",
        change24h: Double?,
        weekly: Double?,
        monthly: Double?,
        threeMonth: Double?,
        ytd: Double?,
        yearly: Double?,
        fiveYear: Double?,
        forwardPE: Double?,
        eps: Double?,
        forwardEps: Double?,
        pbvRatio: Double?,
        freeCashflow: Double?,
        trailingPE: Double?,
        roe: Double?,
        marketCap: Double?,
        dividendYield: Double?,
        sector: String
    ) {
        let upper = ticker.uppercased()
        let changePct = change24h ?? 0.0
        let prevClose = (changePct != 0 && (1.0 + (changePct / 100.0)) > 0) ? (price / (1.0 + (changePct / 100.0))) : price
        let quote = StockQuote(
            ticker: upper,
            name: name,
            price: price,
            previousClose: prevClose,
            open: price,
            high: price,
            low: price,
            volume: 10_000_000,
            currency: currency
        )
        self.quotes[upper] = quote
        self.priceDirections[upper] = .unchanged

        let w = weekly ?? 0.0
        let m = monthly ?? 0.0
        let y = ytd ?? 0.0
        let yr = yearly ?? 0.0
        Self.performanceData[upper] = (w, m, y, yr, threeMonth, fiveYear)

        let fund = StockFundamentals(
            ticker: upper,
            name: name,
            peRatio: trailingPE ?? 0.0,
            eps: eps ?? 0.0,
            marketCap: (marketCap ?? 0.0) / 1_000_000_000_000.0,
            dividendYield: dividendYield ?? 0.0,
            beta: 1.0,
            pbvRatio: pbvRatio ?? 0.0,
            roe: roe ?? 0.0,
            debtToEquity: 1.0,
            sector: sector,
            forwardPE: forwardPE,
            forwardEps: forwardEps,
            freeCashflow: freeCashflow
        )
        Self.fundamentalsData[upper] = fund
        self.lastTick = Date()
    }

    // MARK: - Private Tick Logic

    @MainActor
    private func simulateMarketTick() {
        lastTick = Date()

        let allTickers = Array(quotes.keys)
        let countToUpdate = Int.random(in: 3...6)
        let sampledTickers = allTickers.shuffled().prefix(countToUpdate)

        for ticker in sampledTickers {
            guard var quote = quotes[ticker] else { continue }

            let tick = idxTickSize(for: quote.price)
            let steps = [-2, -1, -1, 0, 1, 1, 2].randomElement() ?? 0

            guard steps != 0 else {
                priceDirections[ticker] = .unchanged
                continue
            }

            let delta = Double(steps) * tick
            let newPrice = max(tick, quote.price + delta)

            priceDirections[ticker] = steps > 0 ? .up : .down
            quote.price = newPrice
            quote.high = max(quote.high, newPrice)
            quote.low = min(quote.low, newPrice)
            quote.volume += Int.random(in: 500...20_000)
            quotes[ticker] = quote
        }
    }

    private func idxTickSize(for price: Double) -> Double {
        switch price {
        case ..<200: return 1.0
        case ..<500: return 2.0
        case ..<2_000: return 5.0
        case ..<5_000: return 10.0
        default: return 25.0
        }
    }

    // MARK: - Static Data

    private static func makeInitialQuotes() -> [String: StockQuote] {
        [
            "BBCA": StockQuote(ticker: "BBCA", name: "Bank Central Asia", price: 10_125, previousClose: 10_050, open: 10_075, high: 10_200, low: 10_000, volume: 15_234_500),
            "BBRI": StockQuote(ticker: "BBRI", name: "Bank Rakyat Indonesia", price: 5_250, previousClose: 5_175, open: 5_200, high: 5_300, low: 5_150, volume: 42_567_800),
            "TLKM": StockQuote(ticker: "TLKM", name: "Telkom Indonesia", price: 3_750, previousClose: 3_800, open: 3_790, high: 3_820, low: 3_720, volume: 28_901_200),
            "ASII": StockQuote(ticker: "ASII", name: "Astra International", price: 5_575, previousClose: 5_500, open: 5_525, high: 5_600, low: 5_475, volume: 8_765_400),
            "UNVR": StockQuote(ticker: "UNVR", name: "Unilever Indonesia", price: 3_450, previousClose: 3_500, open: 3_480, high: 3_520, low: 3_430, volume: 5_432_100),
            "BMRI": StockQuote(ticker: "BMRI", name: "Bank Mandiri", price: 6_725, previousClose: 6_650, open: 6_675, high: 6_775, low: 6_625, volume: 18_345_600),
            "GOTO": StockQuote(ticker: "GOTO", name: "GoTo Gojek Tokopedia", price: 84, previousClose: 82, open: 83, high: 86, low: 81, volume: 1_234_567_000),
            "EMTK": StockQuote(ticker: "EMTK", name: "Elang Mahkota Teknologi", price: 2_125, previousClose: 2_100, open: 2_110, high: 2_150, low: 2_075, volume: 3_456_700),
            "BREN": StockQuote(ticker: "BREN", name: "Barito Renewables", price: 7_850, previousClose: 7_700, open: 7_750, high: 7_900, low: 7_650, volume: 12_345_600),
            "AMMN": StockQuote(ticker: "AMMN", name: "Amman Mineral", price: 9_200, previousClose: 9_350, open: 9_300, high: 9_375, low: 9_150, volume: 9_876_500),
            "ACES": StockQuote(ticker: "ACES", name: "Ace Hardware Indonesia", price: 720, previousClose: 710, open: 715, high: 730, low: 705, volume: 6_543_200),
            "ICBP": StockQuote(ticker: "ICBP", name: "Indofood CBP", price: 11_400, previousClose: 11_250, open: 11_300, high: 11_475, low: 11_200, volume: 4_321_000)
        ]
    }

    private static var fundamentalsData: [String: StockFundamentals] = [
        "BBCA": StockFundamentals(ticker: "BBCA", name: "Bank Central Asia", peRatio: 24.5, eps: 413.3, marketCap: 1_250, dividendYield: 2.1, beta: 0.85, pbvRatio: 4.8, roe: 20.5, debtToEquity: 5.2, sector: "Financials"),
        "BBRI": StockFundamentals(ticker: "BBRI", name: "Bank Rakyat Indonesia", peRatio: 14.2, eps: 369.7, marketCap: 790, dividendYield: 3.5, beta: 1.1, pbvRatio: 2.5, roe: 18.8, debtToEquity: 5.8, sector: "Financials"),
        "TLKM": StockFundamentals(ticker: "TLKM", name: "Telkom Indonesia", peRatio: 16.8, eps: 223.2, marketCap: 370, dividendYield: 4.2, beta: 0.75, pbvRatio: 3.1, roe: 19.2, debtToEquity: 0.8, sector: "Telecommunications"),
        "ASII": StockFundamentals(ticker: "ASII", name: "Astra International", peRatio: 8.5, eps: 655.9, marketCap: 225, dividendYield: 5.8, beta: 1.2, pbvRatio: 1.3, roe: 15.6, debtToEquity: 1.1, sector: "Consumer Cyclical"),
        "UNVR": StockFundamentals(ticker: "UNVR", name: "Unilever Indonesia", peRatio: 28.3, eps: 121.9, marketCap: 132, dividendYield: 6.5, beta: 0.55, pbvRatio: 25.1, roe: 88.7, debtToEquity: 2.5, sector: "Consumer Defensive"),
        "BMRI": StockFundamentals(ticker: "BMRI", name: "Bank Mandiri", peRatio: 11.8, eps: 569.9, marketCap: 628, dividendYield: 4.0, beta: 1.05, pbvRatio: 2.1, roe: 18.2, debtToEquity: 6.1, sector: "Financials"),
        "GOTO": StockFundamentals(ticker: "GOTO", name: "GoTo Gojek Tokopedia", peRatio: -42.0, eps: -2.0, marketCap: 98, dividendYield: 0.0, beta: 1.8, pbvRatio: 1.8, roe: -4.5, debtToEquity: 0.3, sector: "Technology"),
        "EMTK": StockFundamentals(ticker: "EMTK", name: "Elang Mahkota Teknologi", peRatio: 18.5, eps: 114.9, marketCap: 45, dividendYield: 0.5, beta: 1.3, pbvRatio: 1.6, roe: 8.7, debtToEquity: 0.4, sector: "Technology")
    ]

    private static var performanceData: [String: (weekly: Double, monthly: Double, ytd: Double, yearly: Double, threeMonth: Double?, fiveYear: Double?)] = [
        "BBCA": (2.1, 4.3, 12.8, 18.5, nil, nil),
        "BBRI": (3.2, 5.1, 8.5, 14.2, nil, nil),
        "TLKM": (-2.5, -3.8, -5.2, -8.1, nil, nil),
        "ASII": (1.8, 3.2, 7.2, 11.5, nil, nil),
        "UNVR": (-3.1, -5.5, -9.2, -15.3, nil, nil),
        "BMRI": (2.8, 4.8, 10.2, 16.8, nil, nil),
        "GOTO": (5.0, 10.5, 25.4, 40.2, nil, nil),
        "EMTK": (3.5, 8.9, 15.1, 22.3, nil, nil)
    ]
}
