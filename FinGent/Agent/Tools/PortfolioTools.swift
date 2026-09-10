// Agent/Tools/PortfolioTools.swift

import Foundation
import FoundationModels

// MARK: - 1. GetPortfolioSummary

struct GetPortfolioSummaryTool: Tool {
    let name = "getPortfolioSummary"
    let description = "Gets the overall portfolio summary. Use ONLY when user explicitly asks about overall portfolio summary or total net worth, NOT for specific stock questions."

    @Generable struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        let holdings = await MainActor.run { PortfolioRepository.shared.userHoldings }
        guard !holdings.isEmpty else {
            return "Portofolio kamu saat ini masih kosong (0 saham). Tambahkan saham terlebih dahulu."
        }
        let resolved = resolveHoldings(holdings)
        let totalMarket = resolved.reduce(0) { $0 + $1.marketValue }
        let totalCost = resolved.reduce(0) { $0 + $1.totalCost }
        let totalPnL = totalMarket - totalCost
        let pnlPct = totalCost > 0 ? (totalPnL / totalCost) * 100 : 0

        return """
        Portfolio Summary:
        - Total Holdings: \(holdings.count) stocks
        - Total Market Value: Rp \(formatNumber(totalMarket))
        - Total Cost Basis: Rp \(formatNumber(totalCost))
        - Total P&L: Rp \(formatNumber(totalPnL)) (\(String(format: "%.2f", pnlPct))%)
        - Status: \(totalPnL >= 0 ? "PROFIT 📈" : "LOSS 📉")
        """
    }
}

// MARK: - 2. GetHolding

struct GetHoldingTool: Tool {
    let name = "getHolding"
    let description = "Gets details of a specific stock holding by ticker symbol (e.g. 'MU', 'BBCA'). Only use 'ALL' when the user explicitly asks to view all portfolio holdings."

    @Generable struct Arguments {
        @Guide(description: "The stock ticker symbol to look up, e.g. 'MU' or 'BBCA'. Use 'ALL' ONLY if user asks to see all holdings.")
        var ticker: String
    }

    func call(arguments: Arguments) async throws -> String {
        let holdings = await MainActor.run { PortfolioRepository.shared.userHoldings }
        guard !holdings.isEmpty else {
            return "Portofolio kamu saat ini belum memiliki saham."
        }
        let resolved = resolveHoldings(holdings)
        let rawTicker = arguments.ticker.trimmingCharacters(in: .whitespaces)

        if rawTicker.uppercased() == "ALL" {
            var result = "All Portfolio Holdings:\n"
            for h in resolved {
                result += """
                \n- \(h.ticker) (\(h.name)):
                  Shares: \(h.shares) | Avg: Rp \(formatNumber(h.avgPrice)) | Current: Rp \(formatNumber(h.currentPrice))
                  Market Value: Rp \(formatNumber(h.marketValue)) | P&L: Rp \(formatNumber(h.unrealizedGain)) (\(String(format: "%.2f", h.unrealizedGainPercent))%)
                """
            }
            return result
        }

        // Resolve ticker symbol / company alias (e.g. 'micron' -> 'MU')
        let targetTicker = StockTickerExtractor().extractTickers(from: rawTicker).first ?? rawTicker.uppercased()

        guard let holding = resolved.first(where: { $0.ticker.uppercased() == targetTicker }) else {
            return "Kamu saat ini tidak memiliki posisi saham '\(targetTicker)' di portofolio."
        }

        return """
        Holding Detail — \(holding.ticker) (\(holding.name)):
        - Sector: \(holding.sector)
        - Shares: \(holding.shares)
        - Average Purchase Price: Rp \(formatNumber(holding.avgPrice))
        - Current Price: Rp \(formatNumber(holding.currentPrice))
        - Total Cost: Rp \(formatNumber(holding.totalCost))
        - Market Value: Rp \(formatNumber(holding.marketValue))
        - Unrealized P&L: Rp \(formatNumber(holding.unrealizedGain)) (\(String(format: "%.2f", holding.unrealizedGainPercent))%)
        """
    }
}

// MARK: - 3. GetPortfolioPerformance

struct GetPortfolioPerformanceTool: Tool {
    let name = "getPortfolioPerformance"
    let description = "Gets portfolio performance (return percentage) for a given time period. Valid periods: daily, weekly, monthly, ytd, yearly."

    @Generable struct Arguments {
        @Guide(description: "Time period: daily, weekly, monthly, ytd, or yearly.")
        var period: String
    }

    func call(arguments: Arguments) async throws -> String {
        let holdings = await MainActor.run { PortfolioRepository.shared.userHoldings }
        guard !holdings.isEmpty else { return "Portofolio kamu saat ini belum memiliki saham." }

        let resolved = resolveHoldings(holdings)
        let data = MarketDataRepository.shared
        let totalValue = resolved.reduce(0) { $0 + $1.marketValue }

        var weightedReturn = 0.0
        var totalWeight = 0.0

        for h in resolved {
            guard let perf = data.getPerformance(for: h.ticker) else { continue }
            let weight = totalValue > 0 ? h.marketValue / totalValue : 0
            weightedReturn += periodReturn(perf, period: arguments.period) * weight
            totalWeight += weight
        }

        let portfolioReturn = totalWeight > 0 ? weightedReturn / totalWeight : 0
        var result = "Portfolio Performance (\(arguments.period)):\n- Portfolio Return: \(String(format: "%.2f", portfolioReturn))%\n\nPer-Stock Breakdown:\n"
        for h in resolved {
            guard let perf = data.getPerformance(for: h.ticker) else { continue }
            result += "- \(h.ticker): \(String(format: "%+.2f", periodReturn(perf, period: arguments.period)))%\n"
        }
        return result
    }

    private func periodReturn(_ perf: StockPerformance, period: String) -> Double {
        switch period.lowercased() {
        case "weekly": return perf.weekly
        case "monthly": return perf.monthly
        case "ytd": return perf.ytd
        case "yearly": return perf.yearly
        default: return perf.daily
        }
    }
}

// MARK: - 4. GetPortfolioAllocation

struct GetPortfolioAllocationTool: Tool {
    let name = "getPortfolioAllocation"
    let description = "Gets the portfolio allocation breakdown by sector and stock. Use ONLY when user explicitly asks about overall portfolio allocation."

    @Generable struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        let holdings = await MainActor.run { PortfolioRepository.shared.userHoldings }
        guard !holdings.isEmpty else { return "Portofolio kamu saat ini belum memiliki saham." }
        let resolved = resolveHoldings(holdings)
        let totalValue = resolved.reduce(0) { $0 + $1.marketValue }
        guard totalValue > 0 else { return "Total nilai portofolio adalah Rp 0." }

        var sectorAlloc: [String: Double] = [:]
        for h in resolved { sectorAlloc[h.sector, default: 0] += h.marketValue }

        var result = "Portfolio Allocation:\n\nBy Sector:\n"
        for (sector, value) in sectorAlloc.sorted(by: { $0.value > $1.value }) {
            result += "- \(sector): Rp \(formatNumber(value)) (\(String(format: "%.1f", (value / totalValue) * 100))%)\n"
        }
        result += "\nBy Stock:\n"
        for h in resolved.sorted(by: { $0.marketValue > $1.marketValue }) {
            result += "- \(h.ticker) (\(h.name)): Rp \(formatNumber(h.marketValue)) (\(String(format: "%.1f", (h.marketValue / totalValue) * 100))%)\n"
        }
        return result
    }
}

// MARK: - 5. GetPortfolioMovers

struct GetPortfolioMoversTool: Tool {
    let name = "getPortfolioMovers"
    let description = "Gets the top movers (gainers and losers) in the portfolio. Use ONLY when user explicitly asks about portfolio movers."

    @Generable struct Arguments {
        @Guide(description: "Filter direction: 'gainers', 'losers', or 'all'.")
        var direction: String
    }

    func call(arguments: Arguments) async throws -> String {
        let holdings = await MainActor.run { PortfolioRepository.shared.userHoldings }
        guard !holdings.isEmpty else { return "Portofolio kamu saat ini belum memiliki saham." }

        let resolved = resolveHoldings(holdings)
        let data = MarketDataRepository.shared
        let sorted: [(StockHolding, Double)] = resolved
            .compactMap { h in data.getPerformance(for: h.ticker).map { (h, $0.daily) } }
            .sorted { $0.1 > $1.1 }

        var result = "Portfolio Movers (Today):\n"
        let dir = arguments.direction.lowercased()

        if dir == "gainers" || dir == "all" {
            result += "\n📈 Top Gainers:\n"
            for (h, change) in sorted.prefix(3) where change > 0 {
                result += "- \(h.ticker) (\(h.name)): \(String(format: "%+.2f", change))%\n"
            }
        }
        if dir == "losers" || dir == "all" {
            result += "\n📉 Top Losers:\n"
            for (h, change) in sorted.reversed().prefix(3) where change < 0 {
                result += "- \(h.ticker) (\(h.name)): \(String(format: "%+.2f", change))%\n"
            }
        }
        return result
    }
}

// MARK: - 6. GetUnrealizedGain

struct GetUnrealizedGainTool: Tool {
    let name = "getUnrealizedGain"
    let description = "Gets the unrealized gain or loss for a specific stock ticker symbol (e.g. 'MU') or the entire portfolio ('ALL')."

    @Generable struct Arguments {
        @Guide(description: "Stock ticker to check, e.g. 'MU'. Use 'ALL' ONLY if user asks for full portfolio P&L.")
        var ticker: String
    }

    func call(arguments: Arguments) async throws -> String {
        let holdings = await MainActor.run { PortfolioRepository.shared.userHoldings }
        guard !holdings.isEmpty else { return "Portofolio kamu saat ini belum memiliki saham." }
        let resolved = resolveHoldings(holdings)
        let rawTicker = arguments.ticker.trimmingCharacters(in: .whitespaces)

        if rawTicker.uppercased() == "ALL" {
            var result = "Unrealized P&L — Full Portfolio:\n"
            var totalGain = 0.0
            for h in resolved.sorted(by: { $0.unrealizedGain > $1.unrealizedGain }) {
                result += "\(h.unrealizedGain >= 0 ? "🟢" : "🔴") \(h.ticker): Rp \(formatNumber(h.unrealizedGain)) (\(String(format: "%+.2f", h.unrealizedGainPercent))%)\n"
                totalGain += h.unrealizedGain
            }
            let totalCost = resolved.reduce(0) { $0 + $1.totalCost }
            let pct = totalCost > 0 ? (totalGain / totalCost) * 100 : 0
            result += "\nTotal Unrealized P&L: Rp \(formatNumber(totalGain)) (\(String(format: "%+.2f", pct))%)"
            return result
        }

        // Resolve ticker symbol / company alias (e.g. 'micron' -> 'MU')
        let targetTicker = StockTickerExtractor().extractTickers(from: rawTicker).first ?? rawTicker.uppercased()

        guard let h = resolved.first(where: { $0.ticker.uppercased() == targetTicker }) else {
            return "Kamu saat ini tidak memiliki posisi saham '\(targetTicker)' di portofolio."
        }

        return """
        Unrealized P&L — \(h.ticker) (\(h.name)):
        - Shares: \(h.shares)
        - Avg Cost: Rp \(formatNumber(h.avgPrice)) → Current: Rp \(formatNumber(h.currentPrice))
        - Total Cost: Rp \(formatNumber(h.totalCost))
        - Market Value: Rp \(formatNumber(h.marketValue))
        - Unrealized P&L: Rp \(formatNumber(h.unrealizedGain)) (\(String(format: "%+.2f", h.unrealizedGainPercent))%)
        - Status: \(h.unrealizedGain >= 0 ? "PROFIT 🟢" : "LOSS 🔴")
        """
    }
}

// MARK: - Shared Helpers

private func resolveHoldings(_ userHoldings: [UserHolding]) -> [StockHolding] {
    userHoldings.map { h in
        let price = MarketDataRepository.shared.getQuote(for: h.ticker)?.price ?? h.pricePerShare
        return StockHolding(ticker: h.ticker, name: h.name, shares: h.shares, avgPrice: h.pricePerShare, currentPrice: price, sector: h.sector)
    }
}

nonisolated private func formatNumber(_ value: Double) -> String {
    NumberFormatters.stockPrice(value)
}
