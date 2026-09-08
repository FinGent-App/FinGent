// Core/Domain/Repository/PortfolioRepositoryProtocol.swift

import Foundation

protocol PortfolioRepositoryProtocol: AnyObject, Sendable {
    var userHoldings: [UserHolding] { get }
    var userName: String { get set }
    var portfolioValue: Double { get set }

    func addHolding(ticker: String, name: String, amount: Double, pricePerShare: Double, sector: String)
    func updateShares(ticker: String, newShares: Double)
    func updateHoldingDetails(ticker: String, pricePerShare: Double, totalInvested: Double)
    func updateHoldingLots(ticker: String, lots: [PurchaseLot], pricePerShare: Double, totalInvested: Double)
    func removeHolding(ticker: String)
}
