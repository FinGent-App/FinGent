// Features/AddStock/ViewModel/AddStockViewModel.swift

import Foundation
import Observation

@Observable
@MainActor
final class AddStockViewModel {

    // MARK: - Dependencies

    private let portfolioUseCase: PortfolioUseCase
    private let marketDataRepository: MarketDataRepositoryProtocol

    // MARK: - Constants

    private static let supportedTickers = [
        "BBCA", "BBRI", "TLKM", "ASII", "UNVR", "BMRI",
        "GOTO", "EMTK", "BREN", "AMMN", "ACES", "ICBP"
    ]

    static let quickAmounts: [(label: String, amount: Double)] = [
        ("100rb", 100_000),
        ("500rb", 500_000),
        ("1jt", 1_000_000),
        ("5jt", 5_000_000),
        ("10jt", 10_000_000)
    ]

    // MARK: - Output State

    private(set) var availableStocks: [AvailableStock] = []
    private(set) var filteredStocks: [AvailableStock] = []
    private(set) var selectedStock: AvailableStock? = nil

    var searchText: String = "" {
        didSet { applyFilter() }
    }

    var amountText: String = "" {
        didSet { formatAmountIfNeeded(oldValue: oldValue) }
    }

    var inputAmount: Double {
        NumberFormatters.parseInput(amountText)
    }

    var estimatedShares: Int {
        guard let stock = selectedStock, stock.price > 0 else { return 0 }
        return Int(inputAmount / stock.price)
    }

    var effectiveInvestment: Double {
        guard let stock = selectedStock else { return 0 }
        return Double(estimatedShares) * stock.price
    }

    var canSave: Bool { estimatedShares > 0 }

    var ownedTickers: Set<String> = []

    // MARK: - Init

    init(portfolioUseCase: PortfolioUseCase, marketDataRepository: MarketDataRepositoryProtocol) {
        self.portfolioUseCase = portfolioUseCase
        self.marketDataRepository = marketDataRepository
        loadStocks()
    }

    // MARK: - Actions

    func selectStock(_ stock: AvailableStock) {
        selectedStock = stock
        amountText = ""
    }

    func clearSelection() {
        selectedStock = nil
        amountText = ""
    }

    func addQuickAmount(_ amount: Double) {
        let updated = inputAmount + amount
        amountText = NumberFormatters.inputFormatted(updated)
    }

    func save() {
        guard let stock = selectedStock, canSave else { return }
        portfolioUseCase.addHolding(
            ticker: stock.ticker,
            name: stock.name,
            amount: inputAmount,
            pricePerShare: stock.price,
            sector: stock.sector
        )
    }

    func refreshStocks() {
        loadStocks()
    }

    // MARK: - Private

    private func loadStocks() {
        availableStocks = portfolioUseCase.availableStocks(allTickers: Self.supportedTickers)
        applyFilter()
    }

    private func applyFilter() {
        guard !searchText.isEmpty else {
            filteredStocks = availableStocks
            return
        }
        let query = searchText.lowercased()
        filteredStocks = availableStocks.filter {
            $0.ticker.lowercased().contains(query) || $0.name.lowercased().contains(query)
        }
    }

    private func formatAmountIfNeeded(oldValue: String) {
        let raw = NumberFormatters.parseInput(amountText)
        guard raw > 0 else {
            if NumberFormatters.parseInput(oldValue) > 0 { amountText = "" }
            return
        }
        let formatted = NumberFormatters.inputFormatted(raw)
        if amountText != formatted { amountText = formatted }
    }
}
