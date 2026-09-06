// Core/Domain/Models/StockQuote.swift

import Foundation

struct StockQuote: Sendable {
    let ticker: String
    let name: String
    var price: Double
    let previousClose: Double
    let open: Double
    var high: Double
    var low: Double
    var volume: Int
    var currency: String = "IDR"

    var change: Double {
        price - previousClose
    }

    var changePercent: Double {
        guard previousClose > 0 else { return 0 }
        return (change / previousClose) * 100
    }

    var formattedPrice: String {
        if currency.uppercased() == "USD" {
            return String(format: "$%.2f", price)
        } else {
            return "Rp \(NumberFormatters.stockPrice(price))"
        }
    }

    var formattedChange: String {
        if currency.uppercased() == "USD" {
            return String(format: "%@$%.2f", change >= 0 ? "+" : "-", abs(change))
        } else {
            return String(format: "%@Rp %@", change >= 0 ? "+" : "-", NumberFormatters.stockPrice(abs(change)))
        }
    }
}
