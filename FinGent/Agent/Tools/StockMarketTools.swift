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

// MARK: - 3. GetStockFundamentals

struct GetStockFundamentalsTool: Tool {
    let name = "getStockFundamentals"
    let description = "Gets fundamental analysis data for a stock including P/E ratio, EPS, market cap, dividend yield, beta, PBV, ROE, and debt-to-equity ratio."

    @Generable struct Arguments {
        @Guide(description: "The stock ticker symbol.") var ticker: String
    }

    func call(arguments: Arguments) async throws -> String {
        guard let fund = MarketDataRepository.shared.getFundamentals(for: arguments.ticker) else {
            return "No fundamentals data found for ticker '\(arguments.ticker)'."
        }
        return """
        Fundamentals — \(fund.ticker) (\(fund.name)):
        - Sector: \(fund.sector)
        - P/E Ratio: \(String(format: "%.1f", fund.peRatio))x
        - EPS: Rp \(String(format: "%.1f", fund.eps))
        - Market Cap: Rp \(String(format: "%.0f", fund.marketCap)) Trillion
        - Dividend Yield: \(String(format: "%.1f", fund.dividendYield))%
        - Beta: \(String(format: "%.2f", fund.beta))
        - P/BV Ratio: \(String(format: "%.1f", fund.pbvRatio))x
        - ROE: \(String(format: "%.1f", fund.roe))%
        - Debt/Equity: \(String(format: "%.1f", fund.debtToEquity))x
        """
    }
}

// MARK: - 4. CompareStocks

struct CompareStocksTool: Tool {
    let name = "compareStocks"
    let description = "Compares two or more stocks side by side. Provide comma-separated ticker symbols."

    @Generable struct Arguments {
        @Guide(description: "Comma-separated ticker symbols, e.g. 'BBCA,BBRI,BMRI'.")
        var tickers: String
    }

    func call(arguments: Arguments) async throws -> String {
        let tickerList = arguments.tickers
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }

        guard tickerList.count >= 2 else {
            return "Please provide at least 2 ticker symbols separated by commas."
        }

        let data = MarketDataRepository.shared
        var result = "Stock Comparison — \(tickerList.joined(separator: " vs ")):\n"

        for ticker in tickerList {
            let quote = data.getQuote(for: ticker)
            let fund = data.getFundamentals(for: ticker)
            let perf = data.getPerformance(for: ticker)
            let price = quote.map { formatNumber($0.price) } ?? "N/A"
            let pe = fund.map { String(format: "%.1f", $0.peRatio) } ?? "N/A"
            let mktCap = fund.map { String(format: "%.0f", $0.marketCap) } ?? "N/A"
            let divYield = fund.map { String(format: "%.1f", $0.dividendYield) } ?? "N/A"
            let daily = perf.map { String(format: "%+.2f", $0.daily) } ?? "N/A"
            result += "\(ticker): Price Rp \(price) | P/E \(pe)x | MktCap Rp \(mktCap)T | DivYld \(divYield)% | Daily \(daily)%\n"
        }
        return result
    }
}

// MARK: - 5. GetMarketMovers

struct GetMarketMoversTool: Tool {
    let name = "getMarketMovers"
    let description = "Gets the top market movers in IHSG. Type: 'gainers', 'losers', or 'active'."

    @Generable struct Arguments {
        @Guide(description: "Type of movers: 'gainers', 'losers', or 'active'.")
        var type: String
    }

    func call(arguments: Arguments) async throws -> String {
        let data = MarketDataRepository.shared
        let movers: [MarketMover]
        let title: String
        switch arguments.type.lowercased() {
        case "losers": movers = data.topLosers; title = "📉 Top Losers (IHSG)"
        case "active": movers = data.mostActive; title = "🔥 Most Active (IHSG)"
        default: movers = data.topGainers; title = "📈 Top Gainers (IHSG)"
        }
        var result = "\(title):\n"
        for (i, mover) in movers.enumerated() {
            result += "\(i + 1). \(mover.ticker) (\(mover.name)): Rp \(formatNumber(mover.price)) (\(String(format: "%+.2f", mover.changePercent))%)\n"
        }
        return result
    }
}

// MARK: - Helpers

nonisolated private func formatNumber(_ value: Double) -> String {
    NumberFormatters.stockPrice(value)
}

nonisolated private func formatVolume(_ volume: Int) -> String {
    NumberFormatters.volume(volume)
}
