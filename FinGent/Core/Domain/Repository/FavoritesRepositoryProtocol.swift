// Core/Domain/Repository/FavoritesRepositoryProtocol.swift

import Foundation

protocol FavoritesRepositoryProtocol: AnyObject, Sendable {
    var favorites: [StockQuote] { get }
    var favoriteTickers: Set<String> { get }

    func isFavorite(ticker: String) -> Bool
    func toggleFavorite(quote: StockQuote)
    func addFavorite(quote: StockQuote)
    func removeFavorite(ticker: String)
}
