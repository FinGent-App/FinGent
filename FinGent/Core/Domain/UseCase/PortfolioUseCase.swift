// Core/Domain/UseCase/PortfolioUseCase.swift

import Foundation

/// Encapsulates portfolio business logic and computes derived values
/// from raw holdings + live market prices.
final class PortfolioUseCase {
    private let portfolioRepository: PortfolioRepositoryProtocol
    private let marketDataRepository: MarketDataRepositoryProtocol

    init(
        portfolioRepository: PortfolioRepositoryProtocol,
        marketDataRepository: MarketDataRepositoryProtocol
    ) {
        self.portfolioRepository = portfolioRepository
        self.marketDataRepository = marketDataRepository
    }

    // MARK: - Holdings with Live Prices

    func resolvedHoldings() -> [StockHolding] {
        portfolioRepository.userHoldings.map { holding in
            let currentPrice = holding.marketPrice
                ?? marketDataRepository.getQuote(for: holding.ticker)?.price
                ?? holding.pricePerShare
            return StockHolding(
                ticker: holding.ticker,
                name: holding.name,
                shares: holding.shares,
                avgPrice: holding.pricePerShare,
                currentPrice: currentPrice,
                sector: holding.sector
            )
        }
    }

    // MARK: - Portfolio Summary

    func portfolioSummary() -> PortfolioSummary {
        let resolved = resolvedHoldings()
        let totalMarketValue = resolved.reduce(0) { $0 + $1.marketValue }
        let totalInvested = portfolioRepository.userHoldings.reduce(0) { $0 + $1.investedAmount }
        return PortfolioSummary(
            totalMarketValue: totalMarketValue,
            totalInvested: totalInvested,
            holdingCount: resolved.count
        )
    }

    // MARK: - Available Stocks for "Add" Flow

    func availableStocks(allTickers: [String]) -> [AvailableStock] {
        allTickers.compactMap { ticker in
            guard let quote = marketDataRepository.getQuote(for: ticker) else { return nil }
            let sector = marketDataRepository.getFundamentals(for: ticker)?.sector ?? "Unknown"
            return AvailableStock(
                ticker: quote.ticker,
                name: quote.name,
                price: quote.price,
                sector: sector,
                currency: quote.currency
            )
        }
    }

    // MARK: - Add / Remove Holdings

    func addHolding(ticker: String, name: String, amount: Double, pricePerShare: Double, sector: String) {
        portfolioRepository.addHolding(
            ticker: ticker,
            name: name,
            amount: amount,
            pricePerShare: pricePerShare,
            sector: sector
        )
    }

    func removeHolding(ticker: String) {
        portfolioRepository.removeHolding(ticker: ticker)
    }

    // MARK: - Weighted Average Merge Logic

    func mergedHolding(existing: UserHolding, addAmount: Double, addPrice: Double) -> UserHolding {
        let newShares = Int(addAmount / addPrice)
        let totalShares = existing.shares + newShares
        let totalInvested = existing.investedAmount + addAmount
        let weightedPrice = totalShares > 0 ? totalInvested / Double(totalShares) : addPrice
        return UserHolding(
            ticker: existing.ticker,
            name: existing.name,
            investedAmount: totalInvested,
            pricePerShare: weightedPrice,
            sector: existing.sector,
            currency: existing.currency
        )
    }
}

// MARK: - Supporting Type

struct AvailableStock {
    let ticker: String
    let name: String
    let price: Double
    let sector: String
    var currency: String = "IDR"

    var isUSD: Bool {
        currency.uppercased() == "USD"
    }

    var formattedPrice: String {
        if isUSD {
            return String(format: "$%.2f", price)
        } else {
            return "Rp \(NumberFormatters.stockPrice(price))"
        }
    }
}
