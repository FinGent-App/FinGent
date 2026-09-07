// Core/Data/Repository/FavoritesRepository.swift

import Foundation
import Observation

@Observable
final class FavoritesRepository: FavoritesRepositoryProtocol, @unchecked Sendable {

    // MARK: - Singleton

    static let shared = FavoritesRepository()

    // MARK: - Persistence Keys

    private enum Key {
        static let favorites = "user_favorites_quotes"
    }

    // MARK: - State

    private(set) var favorites: [StockQuote] = [] {
        didSet {
            saveFavorites()
        }
    }

    var favoriteTickers: Set<String> {
        Set(favorites.map { $0.ticker.uppercased() })
    }

    // MARK: - Init

    private init() {
        self.favorites = Self.loadFavorites()
        // Asynchronously sync with PostgreSQL backend
        Task { [weak self] in
            await self?.syncWithBackend()
        }
    }

    // MARK: - FavoritesRepositoryProtocol

    func isFavorite(ticker: String) -> Bool {
        favoriteTickers.contains(ticker.uppercased())
    }

    func toggleFavorite(quote: StockQuote) {
        if isFavorite(ticker: quote.ticker) {
            removeFavorite(ticker: quote.ticker)
        } else {
            addFavorite(quote: quote)
        }
    }

    func addFavorite(quote: StockQuote) {
        let upper = quote.ticker.uppercased()
        if let idx = favorites.firstIndex(where: { $0.ticker.uppercased() == upper }) {
            favorites[idx] = quote
        } else {
            favorites.append(quote)
        }

        // Sync to PostgreSQL backend
        Task {
            do {
                try await StockApiClient.shared.addToWatchlist(ticker: quote.ticker)
            } catch {
                print("⚠️ [FavoritesRepository] Failed to sync favorite to PostgreSQL: \(error.localizedDescription)")
            }
        }
    }

    func removeFavorite(ticker: String) {
        let upper = ticker.uppercased()
        favorites.removeAll { $0.ticker.uppercased() == upper }

        // Sync removal to PostgreSQL backend
        Task {
            do {
                try await StockApiClient.shared.removeFromWatchlist(ticker: ticker)
            } catch {
                print("⚠️ [FavoritesRepository] Failed to sync removal to PostgreSQL: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - PostgreSQL Cloud Synchronization

    func syncWithBackend() async {
        do {
            let remoteItems = try await StockApiClient.shared.fetchWatchlist()
            let remoteTickers = Set(remoteItems.map { $0.ticker.uppercased() })
            let localTickers = favoriteTickers

            // 1. Push any local favorites that are not yet in PostgreSQL
            for localQuote in favorites where !remoteTickers.contains(localQuote.ticker.uppercased()) {
                try? await StockApiClient.shared.addToWatchlist(ticker: localQuote.ticker)
            }

            // 2. Pull any remote favorites from PostgreSQL that are not in local
            let missingTickers = remoteTickers.subtracting(localTickers)
            if !missingTickers.isEmpty {
                let quotes = try await StockApiClient.shared.fetchBatch(tickers: Array(missingTickers))
                await MainActor.run {
                    for q in quotes {
                        if !self.isFavorite(ticker: q.ticker) {
                            self.favorites.append(q)
                        }
                    }
                }
            }
            print("✅ [FavoritesRepository] Synchronized with PostgreSQL (Total: \(self.favorites.count))")
        } catch {
            print("ℹ️ [FavoritesRepository] Backend offline or unreachable. Using local cache.")
        }
    }

    // MARK: - Local Persistence (Offline-First Fallback)

    private func saveFavorites() {
        guard let data = try? JSONEncoder().encode(favorites) else { return }
        UserDefaults.standard.set(data, forKey: Key.favorites)
    }

    private static func loadFavorites() -> [StockQuote] {
        guard
            let data = UserDefaults.standard.data(forKey: Key.favorites),
            let quotes = try? JSONDecoder().decode([StockQuote].self, from: data)
        else { return [] }
        return quotes
    }
}
