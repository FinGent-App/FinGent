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

    var change: Double {
        price - previousClose
    }

    var changePercent: Double {
        guard previousClose > 0 else { return 0 }
        return (change / previousClose) * 100
    }
}
