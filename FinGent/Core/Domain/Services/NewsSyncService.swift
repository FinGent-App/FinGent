// Core/Domain/Services/NewsSyncService.swift

import Foundation
import os

actor NewsSyncService {

    static let shared = NewsSyncService()

    private let apiClient: StockApiClient
    private let repository: NewsRepositoryProtocol
    private let extractor: TickerExtractor

    private var lastSyncTime: Date?
    private let cacheTTL: TimeInterval = 300 // 5 minutes
    private var isSyncing: Bool = false

    private let logger = Logger(subsystem: "com.suryacenter.FinGent", category: "NewsSyncService")

    init(
        apiClient: StockApiClient = StockApiClient.shared,
        repository: NewsRepositoryProtocol = NewsRepository.shared,
        extractor: TickerExtractor = StockTickerExtractor()
    ) {
        self.apiClient = apiClient
        self.repository = repository
        self.extractor = extractor
    }

    // MARK: - Periodic / Background Sync via Python Backend

    func sync(force: Bool = false) async {
        if !force, let last = lastSyncTime, Date().timeIntervalSince(last) < cacheTTL {
            return
        }

        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            // Fetch clean structured JSON news directly from Python FastAPI Backend
            let backendArticles = try await apiClient.fetchNews(limit: 25)
            if !backendArticles.isEmpty {
                try? await repository.save(backendArticles)
                lastSyncTime = Date()
                logger.info("✅ Synced \(backendArticles.count) news articles from Python backend")
            }
        } catch {
            logger.warning("Backend news sync failed, using local cache: \(error.localizedDescription)")
        }
    }

    // MARK: - On-Demand Ticker Sync via Python Backend

    func syncTicker(ticker: String) async {
        let cleanTicker = ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanTicker.isEmpty else { return }

        do {
            let tickerArticles = try await apiClient.fetchNews(ticker: cleanTicker, limit: 15)
            if !tickerArticles.isEmpty {
                try? await repository.save(tickerArticles)
                logger.info("✅ Synced \(tickerArticles.count) news articles for \(cleanTicker) from Python backend")
            }
        } catch {
            logger.warning("Backend news sync for \(cleanTicker) failed: \(error.localizedDescription)")
        }
    }
}
