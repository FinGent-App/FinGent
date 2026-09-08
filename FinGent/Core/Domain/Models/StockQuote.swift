// Core/Domain/Models/StockQuote.swift

import Foundation

struct StockQuote: Identifiable, Hashable, Sendable, Codable {
    var id: String { ticker }
    let ticker: String
    let name: String
    var price: Double
    let previousClose: Double
    let open: Double
    var high: Double
    var low: Double
    var volume: Int
    var currency: String = "IDR"

    var isUSD: Bool {
        let curr = currency.trimmingCharacters(in: .whitespaces).uppercased()
        if curr == "USD" { return true }
        if curr == "IDR" { return false }
        let upper = ticker.uppercased()
        let knownIndo = ["BBCA", "BBRI", "BMRI", "TLKM", "ASII", "UNVR", "GOTO", "BBNI", "ICBP", "AMMN", "ACES", "BREN", "EMTK", "KLBF", "MDKA", "INDF", "PGAS", "PTBA", "ADRO", "ANTM"]
        return !upper.hasSuffix(".JK") && !knownIndo.contains(upper)
    }

    init(
        ticker: String,
        name: String,
        price: Double,
        previousClose: Double,
        open: Double,
        high: Double,
        low: Double,
        volume: Int,
        currency: String? = nil
    ) {
        self.ticker = ticker
        self.name = name
        self.price = price
        self.previousClose = previousClose
        self.open = open
        self.high = high
        self.low = low
        self.volume = volume

        let upper = ticker.uppercased()
        let knownIndo = ["BBCA", "BBRI", "BMRI", "TLKM", "ASII", "UNVR", "GOTO", "BBNI", "ICBP", "AMMN", "ACES", "BREN", "EMTK", "KLBF", "MDKA", "INDF", "PGAS", "PTBA", "ADRO", "ANTM"]
        if let c = currency, !c.isEmpty {
            self.currency = c.uppercased()
        } else if upper.hasSuffix(".JK") || knownIndo.contains(upper) {
            self.currency = "IDR"
        } else {
            self.currency = "USD"
        }
    }

    var change: Double {
        price - previousClose
    }

    var changePercent: Double {
        guard previousClose > 0 else { return 0 }
        return (change / previousClose) * 100
    }

    var formattedPrice: String {
        if isUSD {
            return String(format: "$%.2f", price)
        } else {
            return "Rp \(NumberFormatters.stockPrice(price))"
        }
    }

    var formattedChange: String {
        if isUSD {
            return String(format: "%@$%.2f", change >= 0 ? "+" : "-", abs(change))
        } else {
            return String(format: "%@Rp %@", change >= 0 ? "+" : "-", NumberFormatters.stockPrice(abs(change)))
        }
    }
}
