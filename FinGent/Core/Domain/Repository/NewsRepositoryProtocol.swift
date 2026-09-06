// Core/Domain/Repository/NewsRepositoryProtocol.swift

import Foundation

protocol NewsRepositoryProtocol: AnyObject {
    var allArticles: [NewsArticle] { get }
    func searchArticles(query: String) -> [NewsArticle]
    func getArticles(for tickers: [String]) -> [NewsArticle]
}
