// Core/Data/Repository/PortfolioRepository.swift

import Foundation
import Observation

@Observable
final class PortfolioRepository: PortfolioRepositoryProtocol, @unchecked Sendable {

    // MARK: - Singleton (needed for AppIntents / cross-process access)

    static let shared = PortfolioRepository()

    // MARK: - Persistence Keys

    private enum Key {
        static let portfolioValue = "portfolio_value"
        static let userName = "user_name"
        static let userHoldings = "user_holdings"
    }

    // MARK: - Observable State

    private(set) var userHoldings: [UserHolding] = [] {
        didSet {
            saveHoldings()
            portfolioValue = totalInvested
        }
    }

    var userName: String {
        didSet {
            UserDefaults.standard.set(userName, forKey: Key.userName)
        }
    }

    var portfolioValue: Double {
        didSet {
            UserDefaults.standard.set(portfolioValue, forKey: Key.portfolioValue)
        }
    }

    // MARK: - Derived

    var totalInvested: Double {
        userHoldings.reduce(0) { $0 + $1.investedAmount }
    }

    var formattedValue: String {
        NumberFormatters.rupiah(portfolioValue)
    }

    // MARK: - Init

    private init() {
        self.portfolioValue = UserDefaults.standard.double(forKey: Key.portfolioValue)
        self.userName = UserDefaults.standard.string(forKey: Key.userName) ?? ""
        self.userHoldings = Self.loadHoldings()
    }

    // MARK: - Portfolio Modification

    func addHolding(ticker: String, name: String, amount: Double, pricePerShare: Double, sector: String) {
        if let index = userHoldings.firstIndex(where: { $0.ticker == ticker }) {
            let existing = userHoldings[index]
            let newShares = Int(amount / pricePerShare)
            let totalShares = existing.shares + newShares
            let totalInvested = existing.investedAmount + amount
            let weightedPrice = totalShares > 0 ? totalInvested / Double(totalShares) : pricePerShare
            userHoldings[index] = UserHolding(
                ticker: ticker,
                name: name,
                investedAmount: totalInvested,
                pricePerShare: weightedPrice,
                sector: sector
            )
        } else {
            userHoldings.append(UserHolding(
                ticker: ticker,
                name: name,
                investedAmount: amount,
                pricePerShare: pricePerShare,
                sector: sector
            ))
        }
    }

    func removeHolding(ticker: String) {
        userHoldings.removeAll { $0.ticker == ticker }
    }

    // MARK: - Persistence

    private func saveHoldings() {
        guard let data = try? JSONEncoder().encode(userHoldings) else { return }
        UserDefaults.standard.set(data, forKey: Key.userHoldings)
    }

    private static func loadHoldings() -> [UserHolding] {
        guard
            let data = UserDefaults.standard.data(forKey: Key.userHoldings),
            let holdings = try? JSONDecoder().decode([UserHolding].self, from: data)
        else { return [] }
        return holdings
    }
}
