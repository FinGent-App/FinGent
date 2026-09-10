// Features/Portfolio/ViewModel/PortfolioViewModel.swift

import Foundation
import Observation

@Observable
@MainActor
final class PortfolioViewModel {

    // MARK: - Dependencies

    private let portfolioRepository: PortfolioRepositoryProtocol
    private let marketDataRepository: MarketDataRepositoryProtocol
    private let portfolioUseCase: PortfolioUseCase

    // MARK: - Output State (observed by View)

    private(set) var userHoldings: [UserHolding] = []
    private(set) var holdingRows: [HoldingRowState] = []
    private(set) var summary: PortfolioSummaryState = .empty
    private(set) var userName: String = ""

    // MARK: - Init

    init(
        portfolioRepository: PortfolioRepositoryProtocol,
        marketDataRepository: MarketDataRepositoryProtocol,
        portfolioUseCase: PortfolioUseCase
    ) {
        self.portfolioRepository = portfolioRepository
        self.marketDataRepository = marketDataRepository
        self.portfolioUseCase = portfolioUseCase
        refresh()
    }

    // MARK: - Actions (called by View)

    func refresh() {
        let repo = portfolioRepository as! PortfolioRepository // @Observable requires concrete type for observation
        userHoldings = repo.userHoldings
        userName = repo.userName
        holdingRows = buildHoldingRows(from: repo.userHoldings)
        summary = buildSummaryState(from: repo)
    }

    func removeHolding(ticker: String) {
        portfolioUseCase.removeHolding(ticker: ticker)
        refresh()
    }

    func updateUserName(_ name: String) {
        (portfolioRepository as? PortfolioRepository)?.userName = name.trimmingCharacters(in: .whitespaces)
    }

    func startMarketSimulation() {
        // Disabled: Uses authentic PostgreSQL prices
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

    private func buildSummaryState(from repo: PortfolioRepository) -> PortfolioSummaryState {
        let holdings = repo.userHoldings
        guard !holdings.isEmpty || repo.portfolioValue > 0 else {
            return .empty
        }

        let resolved = portfolioUseCase.resolvedHoldings()
        let totalMarket = resolved.reduce(0) { $0 + $1.marketValue }
        let totalInvested = holdings.reduce(0) { $0 + $1.investedAmount }
        let totalPnL = totalMarket - totalInvested
        let totalPnLPct = totalInvested > 0 ? (totalPnL / totalInvested) * 100 : 0

        let allUSD = !holdings.isEmpty && holdings.allSatisfy { $0.isUSD }

        let displayValue: String = {
            if !holdings.isEmpty {
                return allUSD ? String(format: "$%.2f", totalMarket) : "Rp \(NumberFormatters.compact(totalMarket))"
            }
            return repo.formattedValue
        }()

        let totalInvestedText = allUSD ? String(format: "$%.2f", totalInvested) : "Rp \(NumberFormatters.compact(totalInvested))"
        let totalPnLText = allUSD
            ? String(format: "%+.1f%% ($%.2f)", totalPnLPct, abs(totalPnL))
            : String(format: "%+.1f%% (Rp %@)", totalPnLPct, NumberFormatters.compact(abs(totalPnL)))

        return PortfolioSummaryState(
            displayValue: displayValue,
            hasValue: true,
            totalInvestedText: totalInvestedText,
            totalPnLText: totalPnLText,
            isPnLProfit: totalPnL >= 0,
            holdingCount: holdings.count,
            totalMarketValue: totalMarket
        )
    }
}

// MARK: - Presentation State Types

struct HoldingRowState: Identifiable {
    var id: String { ticker }
    let ticker: String
    let name: String
    let currentPrice: Double
    let currentValue: Double
    let pnl: Double
    let pnlPercent: Double
    let isProfit: Bool
    let direction: PriceDirection
    let lotText: String
    let formattedPrice: String
    let formattedValue: String
    let formattedPnlPercent: String
    let currency: String
    var dailyChangePercent: Double = 0.0
    var isDailyPositive: Bool = true
}

struct PortfolioSummaryState {
    let displayValue: String
    let hasValue: Bool
    let totalInvestedText: String
    let totalPnLText: String
    let isPnLProfit: Bool
    let holdingCount: Int
    let totalMarketValue: Double

    static let empty = PortfolioSummaryState(
        displayValue: "Belum diatur",
        hasValue: false,
        totalInvestedText: "",
        totalPnLText: "",
        isPnLProfit: true,
        holdingCount: 0,
        totalMarketValue: 0
    )
}
