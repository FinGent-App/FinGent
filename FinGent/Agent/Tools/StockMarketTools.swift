// Agent/Tools/StockMarketTools.swift

import Foundation
import FoundationModels

// MARK: - 1. GetStockQuote

struct GetStockQuoteTool: Tool {
    let name = "getStockQuote"
    let description = "Gets the current stock quote including price, change, volume, and intraday range for a given ticker symbol."

    @Generable struct Arguments {
        @Guide(description: "The stock ticker symbol, e.g. 'BBCA', 'GOTO', 'TLKM'.")
        var ticker: String
    }

    func call(arguments: Arguments) async throws -> String {
        guard let quote = MarketDataRepository.shared.getQuote(for: arguments.ticker) else {
            return "No quote data found for ticker '\(arguments.ticker)'."
        }
        let changeEmoji = quote.change >= 0 ? "📈" : "📉"
        let changeSign = quote.change >= 0 ? "+" : ""
        return """
        Stock Quote — \(quote.ticker) (\(quote.name)) \(changeEmoji):
        - Price: Rp \(formatNumber(quote.price))
        - Change: \(changeSign)Rp \(formatNumber(quote.change)) (\(String(format: "%+.2f", quote.changePercent))%)
        - Previous Close: Rp \(formatNumber(quote.previousClose))
        - Open: Rp \(formatNumber(quote.open))
        - Day Range: Rp \(formatNumber(quote.low)) — Rp \(formatNumber(quote.high))
        - Volume: \(formatVolume(quote.volume))
        """
    }
}

// MARK: - 2. GetStockPerformance

struct GetStockPerformanceTool: Tool {
    let name = "getStockPerformance"
    let description = "Gets the performance (return percentage) of a stock over different time periods: daily, weekly, monthly, ytd, yearly."

    @Generable struct Arguments {
        @Guide(description: "The stock ticker symbol.") var ticker: String
        @Guide(description: "Time period: 'daily', 'weekly', 'monthly', 'ytd', 'yearly', or 'all'.") var period: String
    }

    func call(arguments: Arguments) async throws -> String {
        guard let perf = MarketDataRepository.shared.getPerformance(for: arguments.ticker) else {
            return "No performance data found for ticker '\(arguments.ticker)'."
        }
        if arguments.period.lowercased() == "all" {
            return """
            Stock Performance — \(perf.ticker) (\(perf.name)):
            - Daily:   \(String(format: "%+.2f", perf.daily))%
            - Weekly:  \(String(format: "%+.2f", perf.weekly))%
            - Monthly: \(String(format: "%+.2f", perf.monthly))%
            - YTD:     \(String(format: "%+.2f", perf.ytd))%
            - 1 Year:  \(String(format: "%+.2f", perf.yearly))%
            """
        }
        let value: Double
        let label: String
        switch arguments.period.lowercased() {
        case "weekly": value = perf.weekly; label = "Weekly"
        case "monthly": value = perf.monthly; label = "Monthly"
        case "ytd": value = perf.ytd; label = "Year-to-Date"
        case "yearly": value = perf.yearly; label = "1-Year"
        default: value = perf.daily; label = "Daily"
        }
        return """
        Stock Performance — \(perf.ticker) (\(perf.name)):
        - \(label) Return: \(String(format: "%+.2f", value))%
        - Status: \(value >= 0 ? "UP 📈" : "DOWN 📉")
        """
    }
}

// Note: GetStockFundamentalsTool, CompareStocksTool, and GetMarketMoversTool
// have been migrated to the Python FastAPI Backend & MCP Server.

// MARK: - Helpers

nonisolated private func formatNumber(_ value: Double) -> String {
    NumberFormatters.stockPrice(value)
}

nonisolated private func formatVolume(_ volume: Int) -> String {
    NumberFormatters.volume(volume)
}
