// Core/Domain/Repository/PortfolioRepositoryProtocol.swift

import Foundation

protocol PortfolioRepositoryProtocol: AnyObject, Sendable {
    var userHoldings: [UserHolding] { get }
    var userName: String { get set }
    var portfolioValue: Double { get set }

    func addHolding(ticker: String, name: String, amount: Double, pricePerShare: Double, sector: String)
    func removeHolding(ticker: String)
}
