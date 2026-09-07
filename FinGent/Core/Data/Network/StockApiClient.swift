// Core/Data/Network/StockApiClient.swift

import Foundation

final class StockApiClient: Sendable {

    static let shared = StockApiClient()

    // 127.0.0.1 connects directly to the Mac FastAPI backend from iOS Simulator
    let baseURL: String = "http://127.0.0.1:8000"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - DTOs

    struct QuoteDTO: Decodable, Sendable {
        let ticker: String
        let name: String
        let price: Double
        let previous_close: Double?
        let open: Double?
        let day_high: Double?
        let day_low: Double?
        let volume: Int?
        let currency: String?

        func toDomain() -> StockQuote {
            StockQuote(
                ticker: ticker,
                name: name,
                price: price,
                previousClose: previous_close ?? price,
                open: open ?? price,
                high: day_high ?? price,
                low: day_low ?? price,
                volume: volume ?? 0,
                currency: currency ?? "IDR"
            )
        }
    }

    struct BatchDTO: Decodable, Sendable {
        let count: Int
        let data: [QuoteDTO]
    }

    struct FundamentalsDTO: Decodable, Sendable {
        let ticker: String
        let name: String
        let sector: String
        let pe_ratio: Double
        let pbv_ratio: Double
        let roe: Double
        let market_cap: Double
        let dividend_yield: Double

        func toDomain() -> StockFundamentals {
            StockFundamentals(
                ticker: ticker,
                name: name,
                peRatio: pe_ratio,
                eps: 0.0,
                marketCap: market_cap / 1_000_000_000_000.0,
                dividendYield: dividend_yield,
                beta: 1.0,
                pbvRatio: pbv_ratio,
                roe: roe,
                debtToEquity: 0.0,
                sector: sector
            )
        }
    }

    struct HistoryPointDTO: Decodable, Sendable {
        let timestamp: String
        let price: Double
        let open: Double?
        let high: Double?
        let low: Double?
        let volume: Int?
    }

    struct HistoryResponseDTO: Decodable, Sendable {
        let ticker: String
        let period: String
        let count: Int
        let data: [HistoryPointDTO]
    }

    struct WatchlistItemDTO: Decodable, Sendable {
        let id: String?
        let user_id: String
        let ticker: String
        let notes: String?
        let added_at: String?
    }

    struct WatchlistResponseDTO: Decodable, Sendable {
        let user_id: String
        let count: Int
        let watchlist: [WatchlistItemDTO]
    }

    struct HoldingDTO: Decodable, Sendable {
        let id: String?
        let user_id: String
        let ticker: String
        let name: String
        let shares: Int
        let price_per_share: Double
        let invested_amount: Double
        let sector: String?
        let updated_at: String?
    }

    struct HoldingsResponseDTO: Decodable, Sendable {
        let user_id: String
        let count: Int
        let holdings: [HoldingDTO]
    }

    struct SecFilingDTO: Decodable, Sendable, Identifiable {
        var id: String { "\(type)_\(date)_\(url)" }
        let type: String
        let title: String
        let date: String
        let url: String
    }

    struct SecFilingsResponseDTO: Decodable, Sendable {
        let ticker: String
        let count: Int
        let filings: [SecFilingDTO]
    }

    // MARK: - API Calls

    func fetchQuote(ticker: String) async throws -> StockQuote {
        let clean = ticker.trimmingCharacters(in: .whitespaces).uppercased()
        guard let url = URL(string: "\(baseURL)/api/v1/stocks/\(clean)") else {
            throw URLError(.badURL)
        }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let dto = try JSONDecoder().decode(QuoteDTO.self, from: data)
        return dto.toDomain()
    }

    func fetchBatch(tickers: [String]) async throws -> [StockQuote] {
        let joined = tickers.joined(separator: ",")
        guard let encoded = joined.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(baseURL)/api/v1/stocks/batch?tickers=\(encoded)") else {
            throw URLError(.badURL)
        }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let batch = try JSONDecoder().decode(BatchDTO.self, from: data)
        return batch.data.map { $0.toDomain() }
    }

    func fetchFundamentals(ticker: String) async throws -> StockFundamentals {
        let clean = ticker.trimmingCharacters(in: .whitespaces).uppercased()
        guard let url = URL(string: "\(baseURL)/api/v1/stocks/\(clean)/fundamentals") else {
            throw URLError(.badURL)
        }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let dto = try JSONDecoder().decode(FundamentalsDTO.self, from: data)
        return dto.toDomain()
    }

    func fetchHistory(ticker: String, period: String = "1mo") async throws -> [StockHistoryPoint] {
        let clean = ticker.trimmingCharacters(in: .whitespaces).uppercased()
        let normPeriod = period.lowercased()
        guard let url = URL(string: "\(baseURL)/api/v1/stocks/\(clean)/history?period=\(normPeriod)") else {
            throw URLError(.badURL)
        }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let dto = try JSONDecoder().decode(HistoryResponseDTO.self, from: data)

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let stdFormatter = ISO8601DateFormatter()

        return dto.data.map { point in
            let date = isoFormatter.date(from: point.timestamp)
                ?? stdFormatter.date(from: point.timestamp)
                ?? Date()

            return StockHistoryPoint(
                date: date,
                price: point.price,
                open: point.open ?? point.price,
                high: point.high ?? point.price,
                low: point.low ?? point.price,
                volume: point.volume ?? 0
            )
        }
    }

    // MARK: - Watchlist (PostgreSQL Cloud Sync)

    func fetchWatchlist(userId: String = "default_user") async throws -> [WatchlistItemDTO] {
        guard let url = URL(string: "\(baseURL)/api/v1/watchlist?user_id=\(userId)") else {
            throw URLError(.badURL)
        }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let res = try JSONDecoder().decode(WatchlistResponseDTO.self, from: data)
        return res.watchlist
    }

    func addToWatchlist(ticker: String, notes: String? = nil, userId: String = "default_user") async throws {
        guard let url = URL(string: "\(baseURL)/api/v1/watchlist?user_id=\(userId)") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any?] = ["ticker": ticker.uppercased(), "notes": notes]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload.compactMapValues { $0 })

        let (_, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    func removeFromWatchlist(ticker: String, userId: String = "default_user") async throws {
        let clean = ticker.trimmingCharacters(in: .whitespaces).uppercased()
        guard let url = URL(string: "\(baseURL)/api/v1/watchlist/\(clean)?user_id=\(userId)") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        let (_, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    // MARK: - Portfolio Holdings (PostgreSQL Cloud Sync)

    func fetchHoldings(userId: String = "default_user") async throws -> [HoldingDTO] {
        guard let url = URL(string: "\(baseURL)/api/v1/portfolio/holdings?user_id=\(userId)") else {
            throw URLError(.badURL)
        }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let res = try JSONDecoder().decode(HoldingsResponseDTO.self, from: data)
        return res.holdings
    }

    func saveHolding(
        ticker: String,
        name: String,
        shares: Int,
        pricePerShare: Double,
        investedAmount: Double,
        sector: String = "Technology",
        userId: String = "default_user"
    ) async throws {
        guard let url = URL(string: "\(baseURL)/api/v1/portfolio/holdings?user_id=\(userId)") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "ticker": ticker.uppercased(),
            "name": name,
            "shares": shares,
            "price_per_share": pricePerShare,
            "invested_amount": investedAmount,
            "sector": sector
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (_, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    func deleteHolding(ticker: String, userId: String = "default_user") async throws {
        let clean = ticker.trimmingCharacters(in: .whitespaces).uppercased()
        guard let url = URL(string: "\(baseURL)/api/v1/portfolio/holdings/\(clean)?user_id=\(userId)") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        let (_, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    // MARK: - SEC Filings (10-K, 10-Q, 8-K)

    func fetchSecFilings(ticker: String, limit: Int = 10) async throws -> [SecFilingDTO] {
        let clean = ticker.trimmingCharacters(in: .whitespaces).uppercased()
        guard let url = URL(string: "\(baseURL)/api/v1/stocks/\(clean)/sec?limit=\(limit)") else {
            throw URLError(.badURL)
        }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let res = try JSONDecoder().decode(SecFilingsResponseDTO.self, from: data)
        return res.filings
    }

    // MARK: - RAG DTOs & Vector Knowledge Base (Zilliz Cloud)

    struct RAGCitationDTO: Decodable, Sendable {
        let id: String
        let doc_type: String
        let badge_label: String
        let ticker: String
        let title: String
        let content: String
        let source_url: String
        let score: Double
    }

    struct RAGQueryResponseDTO: Decodable, Sendable {
        let query: String
        let grounding_context: String
        let count: Int
        let citations: [RAGCitationDTO]
    }

    func queryRAG(prompt: String, ticker: String? = nil, userId: String = "default_user", limit: Int = 5) async throws -> RAGQueryResponseDTO {
        guard let url = URL(string: "\(baseURL)/api/v1/rag/query") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload: [String: Any] = [
            "query": prompt,
            "user_id": userId,
            "limit": limit
        ]
        if let ticker = ticker, !ticker.isEmpty {
            payload["ticker"] = ticker.uppercased()
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(RAGQueryResponseDTO.self, from: data)
    }

    func syncRAG(userId: String = "default_user") async throws {
        guard let url = URL(string: "\(baseURL)/api/v1/rag/sync?user_id=\(userId)") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        let (_, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    // MARK: - News Ingestion & Grounding API (Backend Python)

    struct NewsArticleItemDTO: Decodable, Sendable {
        let id: String
        let title: String
        let summary: String?
        let url: String
        let source: String
        let author: String?
        let image_url: String?
        let tickers: [String]?
        let published_at: String

        func toDomain() -> NewsArticle {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var pubDate = formatter.date(from: published_at)
            if pubDate == nil {
                let standardFormatter = ISO8601DateFormatter()
                pubDate = standardFormatter.date(from: published_at) ?? Date()
            }

            let parsedURL = URL(string: url) ?? URL(string: "https://finance.yahoo.com")!
            let parsedSource = NewsSourceType.from(rawString: source)
            let imgURL = image_url.flatMap { URL(string: $0) }

            return NewsArticle(
                id: id,
                title: title,
                summary: summary,
                url: parsedURL,
                source: parsedSource,
                publishedAt: pubDate ?? Date(),
                author: author,
                imageURL: imgURL,
                tickers: tickers ?? [],
                fetchedAt: Date()
            )
        }
    }

    struct NewsResponseDTO: Decodable, Sendable {
        let ticker: String?
        let count: Int
        let articles: [NewsArticleItemDTO]
    }

    func fetchNews(ticker: String? = nil, limit: Int = 15) async throws -> [NewsArticle] {
        var urlStr = "\(baseURL)/api/v1/news?limit=\(limit)"
        if let ticker = ticker, !ticker.isEmpty {
            let clean = ticker.trimmingCharacters(in: .whitespaces).uppercased().replacingOccurrences(of: ".JK", with: "")
            urlStr += "&ticker=\(clean)"
        }
        guard let url = URL(string: urlStr) else {
            throw URLError(.badURL)
        }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let res = try JSONDecoder().decode(NewsResponseDTO.self, from: data)
        return res.articles.map { $0.toDomain() }
    }
}
