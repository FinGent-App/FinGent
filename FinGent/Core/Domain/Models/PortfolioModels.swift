// Core/Domain/Models/PortfolioModels.swift

import Foundation

// MARK: - UserHolding (persisted, user-facing)

struct UserHolding: Codable, Identifiable, Sendable, Equatable {
    var id: String { ticker }
    let ticker: String
    let name: String
    var investedAmount: Double
    let pricePerShare: Double
    let sector: String

    var shares: Int {
        guard pricePerShare > 0 else { return 0 }
        return Int(investedAmount / pricePerShare)
    }

    var lots: Int {
        shares / 100
    }

    func currentValue(at currentPrice: Double) -> Double {
        Double(shares) * currentPrice
    }

    func pnl(at currentPrice: Double) -> Double {
        currentValue(at: currentPrice) - Double(shares) * pricePerShare
    }

    func pnlPercent(at currentPrice: Double) -> Double {
        let cost = Double(shares) * pricePerShare
        guard cost > 0 else { return 0 }
        return (pnl(at: currentPrice) / cost) * 100
    }
}

// MARK: - StockHolding (AI tools / computed view)

struct StockHolding: Sendable {
    let ticker: String
    let name: String
    let shares: Int
    let avgPrice: Double
    let currentPrice: Double
    let sector: String

    var marketValue: Double { Double(shares) * currentPrice }
    var totalCost: Double { Double(shares) * avgPrice }
    var unrealizedGain: Double { marketValue - totalCost }
    var unrealizedGainPercent: Double {
        guard totalCost > 0 else { return 0 }
        return (unrealizedGain / totalCost) * 100
    }
}

// MARK: - Portfolio Summary

struct PortfolioSummary: Sendable {
    let totalMarketValue: Double
    let totalInvested: Double
    let holdingCount: Int

    var totalPnL: Double { totalMarketValue - totalInvested }
    var totalPnLPercent: Double {
        guard totalInvested > 0 else { return 0 }
        return (totalPnL / totalInvested) * 100
    }
    var isProfit: Bool { totalPnL >= 0 }
}
