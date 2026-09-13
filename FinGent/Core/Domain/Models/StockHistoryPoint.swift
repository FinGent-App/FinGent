// Core/Domain/Models/StockHistoryPoint.swift

import Foundation

struct StockHistoryPoint: Identifiable, Hashable, Sendable {
    let id: UUID
    let date: Date
    let price: Double
    let open: Double
    let high: Double
    let low: Double
    let volume: Int
    var close: Double { price }

    init(
        id: UUID = UUID(),
        date: Date,
        price: Double,
        open: Double = 0,
        high: Double = 0,
        low: Double = 0,
        volume: Int = 0
    ) {
        self.id = id
        self.date = date
        self.price = price
        self.open = open == 0 ? price : open
        self.high = high == 0 ? price : high
        self.low = low == 0 ? price : low
        self.volume = volume
    }
}
