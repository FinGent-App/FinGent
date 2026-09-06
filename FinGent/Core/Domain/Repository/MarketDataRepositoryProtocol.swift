// Core/Domain/Repository/MarketDataRepositoryProtocol.swift

import Foundation

protocol MarketDataRepositoryProtocol: AnyObject {
    var quotes: [String: StockQuote] { get }
    var priceDirections: [String: PriceDirection] { get }

    func getQuote(for ticker: String) -> StockQuote?
    func getFundamentals(for ticker: String) -> StockFundamentals?
    func getPerformance(for ticker: String) -> StockPerformance?

    var topGainers: [MarketMover] { get }
    var topLosers: [MarketMover] { get }
    var mostActive: [MarketMover] { get }

    func startRealtimeSimulation()
    func stopRealtimeSimulation()
}
