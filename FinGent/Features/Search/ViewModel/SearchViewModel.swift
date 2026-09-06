// Features/Search/ViewModel/SearchViewModel.swift

import Foundation
import Observation


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

    private(set) var filteredQuotes: [StockQuote] = []
    private(set) var isSearching: Bool = false
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
        self.filteredQuotes = []
    }

    private var searchTask: Task<Void, Never>?

    // MARK: - Filter Logic

    func applyFilter() {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()

        searchTask?.cancel()

        guard !q.isEmpty else {
            filteredQuotes = []
            isSearching = false
            return
        }

        // 1. Filter locally if any already registered/cached matching query
        let allQuotes = Array(marketDataRepository.quotes.values).sorted(by: { $0.ticker < $1.ticker })
        let localMatches = allQuotes.filter { quote in
            quote.ticker.lowercased().contains(q) || quote.name.lowercased().contains(q)
        }
        filteredQuotes = localMatches

        // 2. Fetch live from backend for any ticker length
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }

            let ticker = q.uppercased()
            if let remoteQuote = try? await StockApiClient.shared.fetchQuote(ticker: ticker) {
                if !Task.isCancelled {
                    var remoteFundamentals: StockFundamentals? = nil
                    if let fund = try? await StockApiClient.shared.fetchFundamentals(ticker: ticker) {
                        remoteFundamentals = fund
                    }
                    (self.marketDataRepository as? MarketDataRepository)?.registerRemoteQuote(remoteQuote, fundamentals: remoteFundamentals)
                    if let idx = self.filteredQuotes.firstIndex(where: { $0.ticker == remoteQuote.ticker }) {
                        self.filteredQuotes[idx] = remoteQuote
                    } else {
                        self.filteredQuotes.insert(remoteQuote, at: 0)
                    }
                }
            }
            if !Task.isCancelled {
                self.isSearching = false
            }
        }
    }

    // MARK: - Details

    func selectStock(_ quote: StockQuote) {
        selectedDetailQuote = quote
        selectedDetailFundamentals = marketDataRepository.getFundamentals(for: quote.ticker)
        selectedDetailPerformance = marketDataRepository.getPerformance(for: quote.ticker)

        if selectedDetailFundamentals == nil {
            Task {
                if let fund = try? await StockApiClient.shared.fetchFundamentals(ticker: quote.ticker) {
                    self.selectedDetailFundamentals = fund
                    (self.marketDataRepository as? MarketDataRepository)?.registerRemoteQuote(quote, fundamentals: fund)
                }
            }
        }
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
