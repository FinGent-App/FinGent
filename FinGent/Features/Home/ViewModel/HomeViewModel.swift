// Features/Home/ViewModel/HomeViewModel.swift

import Foundation
import Observation

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
