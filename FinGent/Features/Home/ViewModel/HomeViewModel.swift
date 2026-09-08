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

    // MARK: - Output State

    private(set) var userName: String = ""
    private(set) var portfolioValue: Double = 0
    private(set) var portfolioInvested: Double = 0
    private(set) var portfolioPnL: Double = 0
    private(set) var portfolioPnLPct: Double = 0
    private(set) var userHoldingsCount: Int = 0
    private(set) var isAllUSD: Bool = false

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
        favoritesRepository: FavoritesRepositoryProtocol = FavoritesRepository.shared
    ) {
        self.portfolioRepository = portfolioRepository
        self.marketDataRepository = marketDataRepository
        self.newsRepository = newsRepository
        self.favoritesRepository = favoritesRepository
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

        topGainers = market.topGainers
        topLosers = market.topLosers
        latestNews = Array(newsRepository.allArticles.prefix(4))

        // Update favorite stocks with live market data when available
        let savedFavorites = favoritesRepository.favorites
        favoriteStocks = savedFavorites.map { saved in
            market.getQuote(for: saved.ticker) ?? saved
        }
    }

    func removeFavorite(ticker: String) {
        favoritesRepository.removeFavorite(ticker: ticker)
        refresh()
    }
}
