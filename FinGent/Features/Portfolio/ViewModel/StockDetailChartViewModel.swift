// Features/Portfolio/ViewModel/StockDetailChartViewModel.swift

import SwiftUI
import Combine

@MainActor
final class StockDetailChartViewModel: ObservableObject, ChartViewModelProtocol {

    // MARK: - Published State

    @Published private(set) var dataPoints: [StockHistoryPoint] = []
    @Published var selectedRange: TimeRange = .oneDay
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String? = nil

    @Published private(set) var oneDayTotalSlots:  Int = 87
    @Published private(set) var oneDayOpenMinutes: Int = 9 * 60   // 09:00 WIB (IDX default)

    private var oneDayOpenDate: Date?

    let quote: StockQuote

    // MARK: - Computed Properties

    var minPrice: Double {
        dataPoints.map(\.price).min() ?? quote.price
    }

    var maxPrice: Double {
        dataPoints.map(\.price).max() ?? quote.price
    }

    var startPrice: Double {
        dataPoints.first?.price ?? quote.previousClose
    }

    var latestPrice: Double {
        dataPoints.last?.price ?? quote.price
    }

    var isPositive: Bool {
        latestPrice >= startPrice
    }

    // MARK: - Init

    init(quote: StockQuote) {
        self.quote = quote
        let isUS = quote.isUSD
        self.oneDayTotalSlots = isUS ? 79 : 87
        self.oneDayOpenMinutes = isUS ? 20 * 60 + 30 : 9 * 60
    }

    // MARK: - Actions

    func fetchChartData() async {
        isLoading = true
        errorMessage = nil

        var rawPoints: [StockHistoryPoint] = []

        do {
            let fetched = try await StockApiClient.shared.fetchHistory(
                ticker: quote.ticker,
                period: selectedRange.apiPeriod
            )
            if !fetched.isEmpty {
                rawPoints = fetched
            }
        } catch {
            // Silently fallback to synthetic data with exact point resolution
        }

        if rawPoints.isEmpty {
            rawPoints = generateFallbackPoints(for: selectedRange)
        }

        let finalPoints = selectedRange == .oneDay ? normalizeToSlots(rawPoints) : rawPoints

        if selectedRange == .oneDay && !rawPoints.isEmpty {
            Stock24hDataService.shared.registerHistory(ticker: quote.ticker, quote: quote, history: rawPoints)
        }

        withAnimation(.easeInOut(duration: 0.25)) {
            self.dataPoints = finalPoints
            self.isLoading = false
        }
    }

    // MARK: - 1D Slot Calculation

    func oneDaySlotIndex(for date: Date) -> Int {
        guard let openDate = oneDayOpenDate else {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "Asia/Jakarta")!
            let h = cal.component(.hour, from: date)
            let m = cal.component(.minute, from: date)
            let mins = (h * 60 + m) - oneDayOpenMinutes
            return max(0, min(mins / 5, oneDayTotalSlots - 1))
        }
        let minutes = date.timeIntervalSince(openDate) / 60.0
        return max(0, min(Int(minutes / 5.0), oneDayTotalSlots - 1))
    }

    private func normalizeToSlots(_ candles: [StockHistoryPoint]) -> [StockHistoryPoint] {
        guard !candles.isEmpty else { return [] }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        let now = Date()

        let openDate = candles[0].date
        let openHour = cal.component(.hour, from: openDate)

        let isUS = quote.isUSD || openHour >= 19 || openHour < 5
        let totalSlots = isUS ? 79 : 87

        let openHourWIB   = cal.component(.hour,   from: openDate)
        let openMinuteWIB = cal.component(.minute, from: openDate)
        let openMins      = openHourWIB * 60 + openMinuteWIB

        self.oneDayTotalSlots  = totalSlots
        self.oneDayOpenMinutes = openMins
        self.oneDayOpenDate    = openDate

        var slots: [StockHistoryPoint?] = Array(repeating: nil, count: totalSlots)

        for candle in candles {
            let idx = oneDaySlotIndex(for: candle.date)
            guard idx >= 0, idx < totalSlots else { continue }
            slots[idx] = candle
        }

        let currentSlotIdx: Int
        if isUS {
            let hoursSinceOpen = now.timeIntervalSince(openDate) / 3600.0
            if hoursSinceOpen >= 0 && hoursSinceOpen < 16 {
                let minutes = now.timeIntervalSince(openDate) / 60.0
                currentSlotIdx = max(0, min(Int(minutes / 5.0), totalSlots - 1))
            } else {
                currentSlotIdx = totalSlots - 1
            }
        } else {
            if cal.isDate(openDate, inSameDayAs: now) {
                let minutes = now.timeIntervalSince(openDate) / 60.0
                let rawIdx  = max(0, min(Int(minutes / 5.0), totalSlots - 1))
                if IDXTradingCalendar.isMiddaySessionBreak(now) {
                    let capMins = IDXTradingCalendar.session1CloseMinutes(now) - openMins
                    let cap     = max(0, min(capMins / 5, totalSlots - 1))
                    currentSlotIdx = min(rawIdx, cap)
                } else {
                    currentSlotIdx = rawIdx
                }
            } else {
                currentSlotIdx = totalSlots - 1
            }
        }

        for i in stride(from: 1, through: currentSlotIdx, by: 1) {
            if slots[i] == nil, let prev = slots[i - 1] {
                let slotDate = openDate.addingTimeInterval(TimeInterval(i * 5 * 60))
                slots[i] = StockHistoryPoint(date: slotDate, price: prev.price, open: prev.price,
                                             high: prev.price, low: prev.price, volume: 0)
            }
        }
        return slots[0...currentSlotIdx].compactMap { $0 }
    }

    // MARK: - Tailored Fallback Points per Timeframe

    private func pointCount(for range: TimeRange) -> Int {
        switch range {
        case .oneDay:     return 87
        case .oneWeek:    return 50
        case .oneMonth:   return 30
        case .threeMonth: return 90
        case .ytd:        return 180
        case .oneYear:    return 252
        case .fiveYear:   return 260
        case .all:        return 260
        }
    }

    private func intervalSeconds(for range: TimeRange) -> Double {
        switch range {
        case .oneDay:     return 5 * 60
        case .oneWeek:    return 30 * 60
        case .oneMonth:   return 24 * 3600
        case .threeMonth: return 24 * 3600
        case .ytd:        return 24 * 3600
        case .oneYear:    return 24 * 3600
        case .fiveYear:   return 7 * 24 * 3600
        case .all:        return 7 * 24 * 3600
        }
    }

    func generateFallbackPoints(for range: TimeRange) -> [StockHistoryPoint] {
        let count = pointCount(for: range)
        let interval = intervalSeconds(for: range)
        let now = Date()

        var points: [StockHistoryPoint] = []
        var runningPrice = quote.previousClose > 0 ? quote.previousClose : quote.price * 0.98
        let stepScale = quote.price * 0.007

        for i in 0..<count {
            let date = now.addingTimeInterval(-Double(count - 1 - i) * interval)
            let delta = Double([-2, -1, 0, 1, 2].randomElement() ?? 0) * stepScale
            runningPrice = max(quote.price * 0.6, runningPrice + delta)

            if i == count - 1 {
                runningPrice = quote.price
            }

            points.append(StockHistoryPoint(
                date: date,
                price: runningPrice,
                open: runningPrice - delta * 0.5,
                high: runningPrice + abs(delta) * 0.4,
                low: runningPrice - abs(delta) * 0.4,
                volume: Int.random(in: 10_000...500_000)
            ))
        }
        return points
    }
}
