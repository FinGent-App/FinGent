// Core/Domain/Models/MarketModels.swift

import Foundation

struct StockFundamentals: Sendable {
    let ticker: String
    let name: String
    let peRatio: Double
    let eps: Double
    let marketCap: Double       // in trillions IDR
    let dividendYield: Double   // percentage
    let beta: Double
    let pbvRatio: Double
    let roe: Double             // percentage
    let debtToEquity: Double
    let sector: String
}

struct StockPerformance: Sendable {
    let ticker: String
    let name: String
    let daily: Double
    let weekly: Double
    let monthly: Double
    let ytd: Double
    let yearly: Double
}

struct MarketMover: Sendable {
    let ticker: String
    let name: String
    let price: Double
    let changePercent: Double
}

enum PriceDirection: Sendable {
    case up
    case down
    case unchanged
}
