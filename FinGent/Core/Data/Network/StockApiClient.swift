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
}
