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
    let forwardPE: Double?
    let forwardEps: Double?
    let freeCashflow: Double?

    init(
        ticker: String,
        name: String,
        peRatio: Double,
        eps: Double,
        marketCap: Double,
        dividendYield: Double,
        beta: Double,
        pbvRatio: Double,
        roe: Double,
        debtToEquity: Double,
        sector: String,
        forwardPE: Double? = nil,
        forwardEps: Double? = nil,
        freeCashflow: Double? = nil
    ) {
        self.ticker = ticker
        self.name = name
        self.peRatio = peRatio
        self.eps = eps
        self.marketCap = marketCap
        self.dividendYield = dividendYield
        self.beta = beta
        self.pbvRatio = pbvRatio
        self.roe = roe
        self.debtToEquity = debtToEquity
        self.sector = sector
        self.forwardPE = forwardPE
        self.forwardEps = forwardEps
        self.freeCashflow = freeCashflow
    }
}

struct StockPerformance: Sendable {
    let ticker: String
    let name: String
    let daily: Double
    let weekly: Double
    let monthly: Double
    let ytd: Double
    let yearly: Double
    let threeMonth: Double?
    let fiveYear: Double?

    init(
        ticker: String,
        name: String,
        daily: Double,
        weekly: Double,
        monthly: Double,
        ytd: Double,
        yearly: Double,
        threeMonth: Double? = nil,
        fiveYear: Double? = nil
    ) {
        self.ticker = ticker
        self.name = name
        self.daily = daily
        self.weekly = weekly
        self.monthly = monthly
        self.ytd = ytd
        self.yearly = yearly
        self.threeMonth = threeMonth
        self.fiveYear = fiveYear
    }
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
