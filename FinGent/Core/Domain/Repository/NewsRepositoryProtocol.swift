// Core/Domain/Repository/NewsRepositoryProtocol.swift

import Foundation

protocol NewsRepositoryProtocol: AnyObject, Sendable {
    var allArticles: [NewsArticle] { get }

    func save(_ articles: [NewsArticle]) async throws
    func articles(
        ticker: String?,
        from: Date?,
        to: Date?,
        source: NewsSourceType?,
        limit: Int
    ) async throws -> [NewsArticle]

    func searchArticles(query: String) -> [NewsArticle]
    func getArticles(for tickers: [String]) -> [NewsArticle]
}
