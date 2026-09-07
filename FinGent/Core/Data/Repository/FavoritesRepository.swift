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
    }

    func removeFavorite(ticker: String) {
        let upper = ticker.uppercased()
        favorites.removeAll { $0.ticker.uppercased() == upper }
    }

    // MARK: - Persistence

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
