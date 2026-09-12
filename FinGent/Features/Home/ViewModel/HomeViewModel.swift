// Features/Home/ViewModel/HomeViewModel.swift

import Foundation
import Observation

enum PortfolioTimeframe: String, CaseIterable, Identifiable {
    case oneDay = "1D"
    case oneWeek = "1W"
    case oneMonth = "1M"
    case threeMonth = "3M"
    case ytd = "YTD"
    case oneYear = "1Y"
    case fiveYear = "5Y"

    var id: String { rawValue }

    func points(isProfit: Bool) -> [CGFloat] {
        let basePoints: [CGFloat]
        switch self {
        case .oneDay:
            basePoints = [0.38, 0.44, 0.36, 0.52, 0.48, 0.60, 0.55, 0.70, 0.74, 0.84]
        case .oneWeek:
            basePoints = [0.28, 0.38, 0.32, 0.48, 0.42, 0.58, 0.52, 0.68, 0.76, 0.86]
        case .oneMonth:
            basePoints = [0.22, 0.32, 0.28, 0.44, 0.40, 0.54, 0.62, 0.60, 0.74, 0.88]
        case .threeMonth:
            basePoints = [0.18, 0.26, 0.38, 0.34, 0.52, 0.50, 0.66, 0.72, 0.84, 0.90]
        case .ytd:
            basePoints = [0.20, 0.30, 0.42, 0.38, 0.56, 0.64, 0.60, 0.76, 0.86, 0.92]
        case .oneYear:
            basePoints = [0.14, 0.24, 0.32, 0.46, 0.42, 0.62, 0.70, 0.78, 0.88, 0.95]
        case .fiveYear:
            basePoints = [0.10, 0.20, 0.28, 0.40, 0.52, 0.64, 0.72, 0.82, 0.90, 0.98]
        }

        if isProfit {
            return basePoints
        } else {
            return basePoints.reversed().map { 1.0 - $0 }
        }
    }
}

@Observable
@MainActor
final class HomeViewModel {

    // MARK: - Dependencies

    private let portfolioRepository: PortfolioRepositoryProtocol
    private let marketDataRepository: MarketDataRepositoryProtocol
    private let newsRepository: NewsRepositoryProtocol
    private let favoritesRepository: FavoritesRepositoryProtocol
    private let portfolioUseCase: PortfolioUseCase?

    // MARK: - Output State

    private(set) var userName: String = ""
    private(set) var portfolioValue: Double = 0
    private(set) var portfolioInvested: Double = 0
    private(set) var portfolioPnL: Double = 0
    private(set) var portfolioPnLPct: Double = 0
    private(set) var dailyPnL: Double = 0
    private(set) var dailyPnLPct: Double = 0
    private(set) var userHoldingsCount: Int = 0
    private(set) var isAllUSD: Bool = false
    private(set) var userHoldings: [UserHolding] = []
    private(set) var holdingRows: [HoldingRowState] = []

    var formattedPortfolioValue: String {
        if isAllUSD {
            return String(format: "$%.2f", portfolioValue)
        } else {
            return NumberFormatters.rupiah(portfolioValue)
        }
    }

    var formattedPnL: String {
        if isAllUSD {
            return String(format: "$%.2f", abs(portfolioPnL))
        } else {
            return NumberFormatters.compact(abs(portfolioPnL))
        }
    }

    var formattedDailyPnL: String {
        if isAllUSD {
            return String(format: "$%.2f", abs(dailyPnL))
        } else {
            return NumberFormatters.compact(abs(dailyPnL))
        }
    }

    func pnl(for timeframe: PortfolioTimeframe) -> (value: Double, percent: Double) {
        switch timeframe {
        case .oneDay:
            return (dailyPnL, dailyPnLPct)
        case .oneWeek:
            let val = dailyPnL * 2.2 + portfolioPnL * 0.15
            let pct = dailyPnLPct * 2.0 + portfolioPnLPct * 0.15
            return (val, pct)
        case .oneMonth:
            let val = dailyPnL * 3.5 + portfolioPnL * 0.35
            let pct = dailyPnLPct * 3.0 + portfolioPnLPct * 0.35
            return (val, pct)
        case .threeMonth:
            let val = portfolioPnL * 0.60 + dailyPnL * 2.0
            let pct = portfolioPnLPct * 0.60 + dailyPnLPct * 1.5
            return (val, pct)
        case .ytd:
            let val = portfolioPnL * 0.75
            let pct = portfolioPnLPct * 0.75
            return (val, pct)
        case .oneYear:
            let val = portfolioPnL * 0.90
            let pct = portfolioPnLPct * 0.90
            return (val, pct)
        case .fiveYear:
            return (portfolioPnL, portfolioPnLPct)
        }
    }

    func formattedPnL(for timeframe: PortfolioTimeframe) -> String {
        let (val, _) = pnl(for: timeframe)
        if isAllUSD {
            return String(format: "$%.2f", abs(val))
        } else {
            return NumberFormatters.compact(abs(val))
        }
    }

    // IHSG Benchmark state
    let ihsgPrice: Double = 8_245.50
    let ihsgChange: Double = 65.20
    let ihsgChangePercent: Double = 0.80

    private(set) var topGainers: [MarketMover] = []
    private(set) var topLosers: [MarketMover] = []
    private(set) var latestNews: [NewsArticle] = []
    private(set) var favoriteStocks: [StockQuote] = []

    // MARK: - Init

    init(
        portfolioRepository: PortfolioRepositoryProtocol,
        marketDataRepository: MarketDataRepositoryProtocol,
        newsRepository: NewsRepositoryProtocol,
        favoritesRepository: FavoritesRepositoryProtocol,
        portfolioUseCase: PortfolioUseCase? = nil
    ) {
        self.portfolioRepository = portfolioRepository
        self.marketDataRepository = marketDataRepository
        self.newsRepository = newsRepository
        self.favoritesRepository = favoritesRepository
        self.portfolioUseCase = portfolioUseCase
        refresh()
    }

    // MARK: - Refresh

    func refresh() {
        let repo = portfolioRepository as! PortfolioRepository
        let holdings = repo.userHoldings
        userName = repo.userName.isEmpty ? "Investor" : repo.userName
        userHoldingsCount = holdings.count
        isAllUSD = !holdings.isEmpty && holdings.allSatisfy { $0.isUSD }

        let market = marketDataRepository
        let totalVal = holdings.reduce(0.0) { sum, h in
            let price = market.getQuote(for: h.ticker)?.price ?? h.pricePerShare
            return sum + (Double(h.shares) * price)
        }
        let totalInv = repo.totalInvested
        portfolioValue = totalVal
        portfolioInvested = totalInv
        portfolioPnL = totalVal - totalInv
        portfolioPnLPct = totalInv > 0 ? (portfolioPnL / totalInv) * 100 : 0

        let totalDailyChange = holdings.reduce(0.0) { sum, h in
            let quote = market.getQuote(for: h.ticker)
            let change = quote?.change ?? 0.0
            return sum + (Double(h.shares) * change)
        }
        dailyPnL = totalDailyChange
        let prevVal = totalVal - totalDailyChange
        dailyPnLPct = prevVal > 0 ? (totalDailyChange / prevVal) * 100 : (totalVal > 0 ? (totalDailyChange / totalVal) * 100 : 0.0)

        userHoldings = holdings
        holdingRows = buildHoldingRows(from: holdings)

        topGainers = market.topGainers
        topLosers = market.topLosers
        latestNews = Array(newsRepository.allArticles.prefix(4))

        // Update favorite stocks with live market data when available
        let savedFavorites = favoritesRepository.favorites
        favoriteStocks = savedFavorites.map { saved in
            market.getQuote(for: saved.ticker) ?? saved
        }
    }

    func removeHolding(ticker: String) {
        if let portfolioUseCase {
            portfolioUseCase.removeHolding(ticker: ticker)
        } else {
            (portfolioRepository as? PortfolioRepository)?.removeHolding(ticker: ticker)
        }
        refresh()
    }

    func removeFavorite(ticker: String) {
        favoritesRepository.removeFavorite(ticker: ticker)
        refresh()
    }

    // MARK: - Private Build Helpers

    private func buildHoldingRows(from holdings: [UserHolding]) -> [HoldingRowState] {
        holdings.map { holding in
            let quote = marketDataRepository.getQuote(for: holding.ticker)
            let currentPrice = holding.marketPrice ?? quote?.price ?? holding.pricePerShare
            let pnl = holding.pnl(at: currentPrice)
            let pnlPct = holding.pnlPercent(at: currentPrice)
            let currentVal = holding.currentValue(at: currentPrice)
            let direction: PriceDirection = pnl > 0 ? .up : (pnl < 0 ? .down : .unchanged)

            let isUSD = holding.isUSD || quote?.isUSD == true
            let curr = isUSD ? "USD" : "IDR"

            let lotText: String = {
                if !isUSD && holding.lots > 0 {
                    return "\(holding.lots) lot (\(NumberFormatters.compact(Double(holding.shares))) lbr)"
                }
                return "\(holding.shares) lbr"
            }()

            let formattedPrice: String = {
                if isUSD {
                    return String(format: "$%.2f", currentPrice)
                } else {
                    return "Rp \(NumberFormatters.stockPrice(currentPrice))"
                }
            }()

            let formattedValue: String = {
                if isUSD {
                    return String(format: "$%.2f", currentVal)
                } else {
                    return "Rp \(NumberFormatters.compact(currentVal))"
                }
            }()

            let dailyChange = quote?.change ?? 0.0
            let dailyChangePct = quote?.changePercent ?? 0.0

            return HoldingRowState(
                ticker: holding.ticker,
                name: holding.name,
                currentPrice: currentPrice,
                currentValue: currentVal,
                pnl: pnl,
                pnlPercent: pnlPct,
                isProfit: pnl >= 0,
                direction: direction,
                lotText: lotText,
                formattedPrice: formattedPrice,
                formattedValue: formattedValue,
                formattedPnlPercent: String(format: "%+.1f%%", pnlPct),
                currency: curr,
                dailyChangePercent: dailyChangePct,
                isDailyPositive: dailyChange >= 0
            )
        }
    }
}
