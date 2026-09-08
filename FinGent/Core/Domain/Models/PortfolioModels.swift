// Core/Domain/Models/PortfolioModels.swift

import Foundation

// MARK: - PurchaseLot (Lot Transaksi Pembelian)

struct PurchaseLot: Codable, Identifiable, Sendable, Equatable {
    var id: UUID = UUID()
    var date: Date = Date()
    var pricePerShare: Double
    var totalInvested: Double

    var shares: Double {
        guard pricePerShare > 0 else { return 0 }
        return totalInvested / pricePerShare
    }
}

// MARK: - UserHolding (persisted, user-facing)

struct UserHolding: Codable, Identifiable, Sendable, Equatable {
    var id: String { ticker }
    let ticker: String
    let name: String
    var investedAmount: Double
    let pricePerShare: Double
    let sector: String
    var currency: String? = nil
    var marketPrice: Double? = nil
    var purchaseLots: [PurchaseLot]? = nil

    var effectiveCurrency: String {
        if let c = currency, !c.isEmpty {
            return c.uppercased()
        }
        let upper = ticker.uppercased()
        let knownIndo = ["BBCA", "BBRI", "BMRI", "TLKM", "ASII", "UNVR", "GOTO", "BBNI", "ICBP", "AMMN", "ACES", "BREN", "EMTK", "KLBF", "MDKA", "INDF", "PGAS", "PTBA", "ADRO", "ANTM"]
        if upper.hasSuffix(".JK") || knownIndo.contains(upper) {
            return "IDR"
        }
        return "USD"
    }

    var isUSD: Bool {
        effectiveCurrency == "USD"
    }

    init(
        ticker: String,
        name: String,
        investedAmount: Double,
        pricePerShare: Double,
        sector: String,
        currency: String? = nil,
        marketPrice: Double? = nil,
        purchaseLots: [PurchaseLot]? = nil
    ) {
        self.ticker = ticker
        self.name = name
        self.investedAmount = investedAmount
        self.pricePerShare = pricePerShare
        self.sector = sector
        self.currency = currency
        self.marketPrice = marketPrice
        self.purchaseLots = purchaseLots
    }

    var shares: Int {
        guard pricePerShare > 0 else { return 0 }
        return Int(investedAmount / pricePerShare)
    }

    var fractionalShares: Double {
        guard pricePerShare > 0 else { return 0 }
        return investedAmount / pricePerShare
    }

    var formattedShares: String {
        let val = fractionalShares
        if val.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(val))"
        } else {
            let str = String(format: "%.2f", val)
            if str.hasSuffix("0") {
                return String(format: "%.1f", val)
            }
            return str
        }
    }

    var lots: Int {
        shares / 100
    }

    func currentValue(at currentPrice: Double) -> Double {
        fractionalShares * currentPrice
    }

    func pnl(at currentPrice: Double) -> Double {
        currentValue(at: currentPrice) - investedAmount
    }

    func pnlPercent(at currentPrice: Double) -> Double {
        guard investedAmount > 0 else { return 0 }
        return (pnl(at: currentPrice) / investedAmount) * 100
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
