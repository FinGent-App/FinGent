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

    // MARK: - Output State

    private(set) var userName: String = ""
    private(set) var portfolioValue: Double = 0
    private(set) var portfolioInvested: Double = 0
    private(set) var portfolioPnL: Double = 0
    private(set) var portfolioPnLPct: Double = 0
    private(set) var userHoldingsCount: Int = 0

    // IHSG Benchmark state
    let ihsgPrice: Double = 8_245.50
    let ihsgChange: Double = 65.20
    let ihsgChangePercent: Double = 0.80

    private(set) var topGainers: [MarketMover] = []
    private(set) var topLosers: [MarketMover] = []
    private(set) var latestNews: [NewsArticle] = []

    // MARK: - Init

    init(
        portfolioRepository: PortfolioRepositoryProtocol,
        marketDataRepository: MarketDataRepositoryProtocol,
        newsRepository: NewsRepositoryProtocol
    ) {
        self.portfolioRepository = portfolioRepository
        self.marketDataRepository = marketDataRepository
        self.newsRepository = newsRepository
        refresh()
    }

    // MARK: - Refresh

    func refresh() {
        let repo = portfolioRepository as! PortfolioRepository
        let holdings = repo.userHoldings
        userName = repo.userName.isEmpty ? "Investor" : repo.userName
        userHoldingsCount = holdings.count

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
    }
}
