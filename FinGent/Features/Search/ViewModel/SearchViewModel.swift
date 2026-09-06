// Features/Search/ViewModel/SearchViewModel.swift

import Foundation
import Observation

enum SearchScope: String, CaseIterable {
    case stocks = "Saham"
    case news = "Berita"
}

@Observable
@MainActor
final class SearchViewModel {

    // MARK: - Dependencies

    private let marketDataRepository: MarketDataRepositoryProtocol
    private let newsRepository: NewsRepositoryProtocol
    private let portfolioUseCase: PortfolioUseCase

    // MARK: - State

    var query: String = "" {
        didSet { applyFilter() }
    }
    var scope: SearchScope = .stocks {
        didSet { applyFilter() }
    }
    var selectedSector: String = "All" {
        didSet { applyFilter() }
    }

    private(set) var filteredQuotes: [StockQuote] = []
    private(set) var filteredNews: [NewsArticle] = []
    private(set) var sectors: [String] = ["All", "Financials", "Technology", "Consumer", "Energy", "Infrastructure"]
    private(set) var selectedDetailQuote: StockQuote?
    private(set) var selectedDetailFundamentals: StockFundamentals?
    private(set) var selectedDetailPerformance: StockPerformance?

    // MARK: - Init

    init(
        marketDataRepository: MarketDataRepositoryProtocol,
        newsRepository: NewsRepositoryProtocol,
        portfolioUseCase: PortfolioUseCase
    ) {
        self.marketDataRepository = marketDataRepository
        self.newsRepository = newsRepository
        self.portfolioUseCase = portfolioUseCase
        applyFilter()
    }

    // MARK: - Filter Logic

    func applyFilter() {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()

        // 1. Filter Stocks
        let allQuotes = Array(marketDataRepository.quotes.values).sorted(by: { $0.ticker < $1.ticker })
        filteredQuotes = allQuotes.filter { quote in
            let matchText = q.isEmpty || quote.ticker.lowercased().contains(q) || quote.name.lowercased().contains(q)
            if selectedSector == "All" {
                return matchText
            } else {
                let sector = marketDataRepository.getFundamentals(for: quote.ticker)?.sector ?? ""
                return matchText && sector.lowercased().contains(selectedSector.lowercased())
            }
        }

        // 2. Filter News
        if q.isEmpty {
            filteredNews = newsRepository.allArticles
        } else {
            filteredNews = newsRepository.searchArticles(query: q)
        }
    }

    // MARK: - Details

    func selectStock(_ quote: StockQuote) {
        selectedDetailQuote = quote
        selectedDetailFundamentals = marketDataRepository.getFundamentals(for: quote.ticker)
        selectedDetailPerformance = marketDataRepository.getPerformance(for: quote.ticker)
    }

    func clearSelection() {
        selectedDetailQuote = nil
        selectedDetailFundamentals = nil
        selectedDetailPerformance = nil
    }

    // MARK: - Quick Add

    func addStockToPortfolio(ticker: String, amount: Double) {
        guard let quote = marketDataRepository.getQuote(for: ticker) else { return }
        let sector = marketDataRepository.getFundamentals(for: ticker)?.sector ?? "General"
        portfolioUseCase.addHolding(
            ticker: ticker,
            name: quote.name,
            amount: amount,
            pricePerShare: quote.price,
            sector: sector
        )
    }
}
