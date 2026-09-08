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

        // Asynchronously sync with PostgreSQL backend
        Task { [weak self] in
            await self?.syncWithBackend()
        }
    }

    // MARK: - Portfolio Modification

    func addHolding(ticker: String, name: String, amount: Double, pricePerShare: Double, sector: String) {
        let savedHolding: UserHolding
        if let index = userHoldings.firstIndex(where: { $0.ticker == ticker }) {
            let existing = userHoldings[index]
            let newShares = Int(amount / pricePerShare)
            let totalShares = existing.shares + newShares
            let totalInvested = existing.investedAmount + amount
            let weightedPrice = totalShares > 0 ? totalInvested / Double(totalShares) : pricePerShare
            let updated = UserHolding(
                ticker: ticker,
                name: name,
                investedAmount: totalInvested,
                pricePerShare: weightedPrice,
                sector: sector
            )
            userHoldings[index] = updated
            savedHolding = updated
        } else {
            let created = UserHolding(
                ticker: ticker,
                name: name,
                investedAmount: amount,
                pricePerShare: pricePerShare,
                sector: sector
            )
            userHoldings.append(created)
            savedHolding = created
        }

        // Sync to PostgreSQL backend
        Task {
            do {
                try await StockApiClient.shared.saveHolding(
                    ticker: savedHolding.ticker,
                    name: savedHolding.name,
                    shares: savedHolding.shares,
                    pricePerShare: savedHolding.pricePerShare,
                    investedAmount: savedHolding.investedAmount,
                    sector: savedHolding.sector
                )
            } catch {
                print("⚠️ [PortfolioRepository] Failed to sync holding to PostgreSQL: \(error.localizedDescription)")
            }
        }
    }

    func removeHolding(ticker: String) {
        userHoldings.removeAll { $0.ticker == ticker }

        // Sync removal to PostgreSQL backend
        Task {
            do {
                try await StockApiClient.shared.deleteHolding(ticker: ticker)
            } catch {
                print("⚠️ [PortfolioRepository] Failed to sync holding deletion to PostgreSQL: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - PostgreSQL Cloud Synchronization

    func syncWithBackend() async {
        do {
            let remoteHoldings = try await StockApiClient.shared.fetchHoldings()

            if remoteHoldings.isEmpty && !userHoldings.isEmpty {
                // 1. Initial migration: Push local holdings to empty PostgreSQL database
                for h in userHoldings {
                    try? await StockApiClient.shared.saveHolding(
                        ticker: h.ticker,
                        name: h.name,
                        shares: h.shares,
                        pricePerShare: h.pricePerShare,
                        investedAmount: h.investedAmount,
                        sector: h.sector
                    )
                }
                print("✅ [PortfolioRepository] Pushed \(userHoldings.count) local holdings to PostgreSQL.")
            } else if !remoteHoldings.isEmpty {
                // 2. Pull remote holdings from PostgreSQL and merge with local state
                let mapped = remoteHoldings.map { dto in
                    UserHolding(
                        ticker: dto.ticker,
                        name: dto.name,
                        investedAmount: dto.invested_amount,
                        pricePerShare: dto.price_per_share,
                        sector: dto.sector ?? "Technology",
                        currency: dto.currency
                    )
                }
                await MainActor.run {
                    self.userHoldings = mapped

                    // 3. Prime MarketDataRepository with enriched performance and fundamentals from PostgreSQL snapshot
                    for dto in remoteHoldings {
                        if let currentPrice = dto.current_price, currentPrice > 0 {
                            let curr = dto.currency ?? (dto.ticker.uppercased() == "MU" ? "USD" : "IDR")
                            MarketDataRepository.shared.registerRemoteHoldingMarketData(
                                ticker: dto.ticker,
                                name: dto.name,
                                price: currentPrice,
                                currency: curr,
                                change24h: dto.change_24h,
                                weekly: dto.change_1w,
                                monthly: dto.change_1m,
                                threeMonth: dto.change_3m,
                                ytd: dto.change_ytd,
                                yearly: dto.change_1y,
                                fiveYear: dto.change_5y,
                                forwardPE: dto.forward_pe,
                                eps: dto.eps,
                                forwardEps: dto.forward_eps,
                                pbvRatio: dto.pbv_ratio,
                                freeCashflow: dto.free_cashflow,
                                trailingPE: dto.trailing_pe,
                                roe: dto.roe,
                                marketCap: dto.market_cap,
                                dividendYield: dto.dividend_yield,
                                sector: dto.sector ?? "Technology"
                            )
                        }
                    }
                }
                print("✅ [PortfolioRepository] Pulled \(mapped.count) holdings & primed market data from PostgreSQL.")
            }
        } catch {
            print("ℹ️ [PortfolioRepository] Backend offline or unreachable. Using local cache.")
        }
    }

    // MARK: - Local Persistence (Offline-First Fallback)

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
