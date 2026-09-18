// Common/Views/Stock24hMiniChartView.swift

import SwiftUI
import Observation

// MARK: - Mini Chart Point

struct MiniChartPoint: Sendable, Hashable {
    let xFraction: CGFloat // 0.0 ... 1.0 along the full trading day
    let normY: CGFloat     // 0.0 ... 1.0 normalized price
}

// MARK: - Stock 24h Stats Model (Matches StockDetailView)

struct Stock24hStats: Sendable, Hashable {
    let points: [MiniChartPoint]
    let startPrice: Double
    let latestPrice: Double
    let change: Double
    let changePercent: Double
    let isPositive: Bool
}

// MARK: - Stock 24h Data Service & In-Memory Cache

@Observable
@MainActor
final class Stock24hDataService {
    static let shared = Stock24hDataService()

    private(set) var statsMap: [String: Stock24hStats] = [:]
    private var inFlight: [String: Task<Stock24hStats?, Never>] = [:]

    private init() {}

    // MARK: - Market Trading Day Calculation

    func isUSStock(ticker: String, quote: StockQuote?) -> Bool {
        if let q = quote { return q.isUSD }
        let upper = ticker.uppercased()
        let knownIndo = ["BBCA", "BBRI", "BMRI", "TLKM", "ASII", "UNVR", "GOTO", "BBNI", "ICBP", "AMMN", "ACES", "BREN", "EMTK", "KLBF", "MDKA", "INDF", "PGAS", "PTBA", "ADRO", "ANTM"]
        return !upper.hasSuffix(".JK") && !knownIndo.contains(upper)
    }

    /// Returns (totalSlots, currentSlot, isMarketOpen)
    /// Respects the 1D / 24h stockDetailView trading rules:
    /// - IDX: 09:00 WIB - 15:50/16:00 WIB (87 slots of 5 mins)
    /// - US:  09:30 EST - 16:00 EST (79 slots of 5 mins)
    func tradingDayInfo(for ticker: String, quote: StockQuote?, relativeTo now: Date = Date()) -> (totalSlots: Int, currentSlot: Int, isMarketOpen: Bool) {
        let isUS = isUSStock(ticker: ticker, quote: quote)

        if isUS {
            let totalSlots = 79 // 6.5 hours = 395 mins / 5 = 79 slots
            var usCal = Calendar(identifier: .gregorian)
            usCal.timeZone = TimeZone(identifier: "America/New_York")!
            let wd = usCal.component(.weekday, from: now)
            if wd == 1 || wd == 7 {
                return (totalSlots, totalSlots - 1, false)
            }
            let mins = usCal.component(.hour, from: now) * 60 + usCal.component(.minute, from: now)
            let openMins = 9 * 60 + 30  // 09:30 EST
            let closeMins = 16 * 60     // 16:00 EST
            if mins >= openMins && mins < closeMins {
                let slot = max(1, min((mins - openMins) / 5, totalSlots - 1))
                return (totalSlots, slot, true)
            } else {
                return (totalSlots, totalSlots - 1, false)
            }
        } else {
            // IDX / Indo Stocks
            let totalSlots = 87 // 09:00 to 16:15
            let cal = IDXTradingCalendar.jakartaCalendar
            if !IDXTradingCalendar.isTradingDay(now) {
                return (totalSlots, totalSlots - 1, false)
            }
            let mins = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
            let openMins = 9 * 60       // 09:00 WIB
            let closeMins = 16 * 60     // 16:00 WIB

            if mins < openMins {
                return (totalSlots, totalSlots - 1, false)
            } else if mins >= closeMins {
                return (totalSlots, totalSlots - 1, false)
            } else {
                var elapsedMins = mins - openMins
                if IDXTradingCalendar.isMiddaySessionBreak(now) {
                    let capMins = IDXTradingCalendar.session1CloseMinutes(now) - openMins
                    elapsedMins = min(elapsedMins, capMins)
                }
                let slot = max(1, min(elapsedMins / 5, totalSlots - 1))
                return (totalSlots, slot, true)
            }
        }
    }

    func stats(for ticker: String, quote: StockQuote?) -> Stock24hStats {
        let clean = ticker.trimmingCharacters(in: .whitespaces).uppercased()
        if let cached = statsMap[clean] {
            return cached
        }
        return generateFallbackStats(ticker: clean, quote: quote)
    }

    func load24hData(ticker: String, quote: StockQuote?) async {
        let clean = ticker.trimmingCharacters(in: .whitespaces).uppercased()
        if statsMap[clean] != nil {
            return
        }

        if let existing = inFlight[clean] {
            _ = await existing.value
            return
        }

        let task = Task<Stock24hStats?, Never> { @MainActor in
            defer { self.inFlight.removeValue(forKey: clean) }
            do {
                let history = try await StockApiClient.shared.fetchHistory(ticker: clean, period: "24h")
                if history.count > 1 {
                    let stats = self.buildStats(ticker: clean, quote: quote, history: history)
                    self.statsMap[clean] = stats
                    return stats
                }
            } catch {
                // Silently fallback on network/backend errors
            }
            return nil
        }

        inFlight[clean] = task
        _ = await task.value
    }

    func registerHistory(ticker: String, quote: StockQuote?, history: [StockHistoryPoint]) {
        guard history.count > 1 else { return }
        let clean = ticker.trimmingCharacters(in: .whitespaces).uppercased()
        let stats = buildStats(ticker: clean, quote: quote, history: history)
        self.statsMap[clean] = stats
    }

    private func buildStats(ticker: String, quote: StockQuote?, history: [StockHistoryPoint]) -> Stock24hStats {
        let (totalSlots, currentSlot, isMarketOpen) = tradingDayInfo(for: ticker, quote: quote)
        let isUS = isUSStock(ticker: ticker, quote: quote)
        let openMins = isUS ? (9 * 60 + 30) : (9 * 60)
        let cal = isUS ? {
            var c = Calendar(identifier: .gregorian)
            c.timeZone = TimeZone(identifier: "America/New_York")!
            return c
        }() : IDXTradingCalendar.jakartaCalendar

        let firstPrice = history.first?.price ?? quote?.previousClose ?? quote?.price ?? 0.0
        let lastPrice = history.last?.price ?? quote?.price ?? firstPrice
        let change = lastPrice - firstPrice
        let changePercent = firstPrice > 0 ? ((lastPrice - firstPrice) / firstPrice) * 100.0 : (quote?.changePercent ?? 0.0)
        let isPositive = change >= 0

        let prices = history.map(\.price)
        let minP = prices.min() ?? firstPrice
        let maxP = prices.max() ?? lastPrice
        let span = maxP - minP

        var mappedPoints: [MiniChartPoint] = []
        for h in history {
            let hMins = cal.component(.hour, from: h.date) * 60 + cal.component(.minute, from: h.date)
            let rawSlot = (hMins - openMins) / 5
            let slot = max(0, min(rawSlot, isMarketOpen ? currentSlot : totalSlots - 1))
            let xFrac = CGFloat(slot) / CGFloat(max(totalSlots - 1, 1))
            let rawNormY = span > 0 ? CGFloat((h.price - minP) / span) : 0.5
            let clampedNormY = 0.08 + rawNormY * 0.84
            mappedPoints.append(MiniChartPoint(xFraction: xFrac, normY: clampedNormY))
        }

        mappedPoints.sort { $0.xFraction < $1.xFraction }

        return Stock24hStats(
            points: mappedPoints,
            startPrice: firstPrice,
            latestPrice: lastPrice,
            change: change,
            changePercent: changePercent,
            isPositive: isPositive
        )
    }

    private func generateFallbackStats(ticker: String, quote: StockQuote?) -> Stock24hStats {
        let (totalSlots, currentSlot, _) = tradingDayInfo(for: ticker, quote: quote)

        let startPrice = (quote?.previousClose != nil && quote!.previousClose > 0) ? quote!.previousClose : (quote?.open ?? quote?.price ?? 0.0)
        let latestPrice = quote?.price ?? startPrice
        let change = quote?.change ?? (latestPrice - startPrice)
        let changePercent = quote?.changePercent ?? (startPrice > 0 ? ((latestPrice - startPrice) / startPrice) * 100.0 : 0.0)
        let isPositive = change >= 0

        var hash: UInt64 = 5381
        for byte in ticker.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }

        let numPoints = max(3, min(currentSlot + 1, 16))
        var points: [MiniChartPoint] = []

        let startVal: CGFloat = isPositive ? 0.32 : 0.68
        let endVal: CGFloat = isPositive ? 0.82 : 0.18

        if let q = quote, q.high > q.low, q.price > 0 {
            let low = q.low
            let high = q.high
            let span = high - low
            let pStart = q.previousClose > 0 ? q.previousClose : (isPositive ? q.price * 0.98 : q.price * 1.02)
            let normStart = CGFloat(max(0.0, min(1.0, (pStart - low) / span)))
            let normEnd = CGFloat(max(0.0, min(1.0, (q.price - low) / span)))

            for i in 0..<numPoints {
                let progress = CGFloat(i) / CGFloat(numPoints - 1)
                let slot = Int(round(progress * CGFloat(currentSlot)))
                let xFrac = CGFloat(slot) / CGFloat(max(totalSlots - 1, 1))

                let base = normStart + (normEnd - normStart) * progress
                let rippleSeed = Double((hash &+ UInt64(i * 31)) % 100) / 100.0
                let wave = sin(Double(i) * 0.9 + Double(hash % 7)) * 0.08
                let jitter = (rippleSeed - 0.5) * 0.06

                var val = base + CGFloat(wave + jitter)
                if i == 0 { val = normStart }
                if i == numPoints - 1 { val = normEnd }

                let clamped = max(0.06, min(0.94, 0.08 + val * 0.84))
                points.append(MiniChartPoint(xFraction: xFrac, normY: clamped))
            }
        } else {
            for i in 0..<numPoints {
                let progress = CGFloat(i) / CGFloat(numPoints - 1)
                let slot = Int(round(progress * CGFloat(currentSlot)))
                let xFrac = CGFloat(slot) / CGFloat(max(totalSlots - 1, 1))

                let base = startVal + (endVal - startVal) * progress
                let rippleSeed = Double((hash &+ UInt64(i * 47)) % 100) / 100.0
                let wave = sin(Double(i) * 0.85 + Double(hash % 5)) * 0.09
                let jitter = (rippleSeed - 0.5) * 0.05

                var val = base + CGFloat(wave + jitter)
                if i == 0 { val = startVal }
                if i == numPoints - 1 { val = endVal }

                let clamped = max(0.06, min(0.94, val))
                points.append(MiniChartPoint(xFraction: xFrac, normY: clamped))
            }
        }

        return Stock24hStats(
            points: points,
            startPrice: startPrice,
            latestPrice: latestPrice,
            change: change,
            changePercent: changePercent,
            isPositive: isPositive
        )
    }
}

// MARK: - Stock 24h Mini Chart View (Sparkline)

struct Stock24hMiniChartView: View {
    let ticker: String
    var quote: StockQuote? = nil
    var stats: Stock24hStats? = nil

    private var currentStats: Stock24hStats {
        stats ?? Stock24hDataService.shared.stats(for: ticker, quote: quote)
    }

    var body: some View {
        let activeStats = currentStats
        let points = activeStats.points
        let isPositive = activeStats.isPositive

        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            if points.count > 1 {
                let coords: [CGPoint] = points.map { pt in
                    let x = pt.xFraction * w
                    let clampedY = max(0.04, min(0.96, pt.normY))
                    let y = h - (clampedY * (h - 4) + 2)
                    return CGPoint(x: x, y: y)
                }

                let strokeColor = isPositive ? Color(hex: "00B89F") : Color(hex: "FF3B30")

                ZStack(alignment: .topLeading) {
                    // Gradient Area Fill under Sparkline
                    Path { path in
                        path.move(to: CGPoint(x: coords[0].x, y: h))
                        path.addLine(to: coords[0])
                        addSmoothCurves(to: &path, with: coords)
                        path.addLine(to: CGPoint(x: coords.last!.x, y: h))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [
                                strokeColor.opacity(isPositive ? 0.25 : 0.20),
                                strokeColor.opacity(0.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    // Line Stroke (thin 0.8pt)
                    Path { path in
                        path.move(to: coords[0])
                        addSmoothCurves(to: &path, with: coords)
                    }
                    .stroke(
                        strokeColor,
                        style: StrokeStyle(lineWidth: 0.8, lineCap: .round, lineJoin: .round)
                    )
                    .shadow(color: strokeColor.opacity(0.12), radius: 1, x: 0, y: 0.5)

                    // Current price indicator dot at latest point
                    if let lastCoord = coords.last {
                        Circle()
                            .fill(strokeColor)
                            .frame(width: 2.5, height: 2.5)
                            .position(lastCoord)
                    }
                }
            }
        }
    }

    private func addSmoothCurves(to path: inout Path, with points: [CGPoint]) {
        guard points.count > 1 else { return }
        for i in 0..<(points.count - 1) {
            let p0 = i > 0 ? points[i - 1] : points[i]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = i < points.count - 2 ? points[i + 2] : p2

            let cp1 = CGPoint(
                x: p1.x + (p2.x - p0.x) / 6,
                y: p1.y + (p2.y - p0.y) / 6
            )
            let cp2 = CGPoint(
                x: p2.x - (p3.x - p1.x) / 6,
                y: p2.y - (p3.y - p1.y) / 6
            )

            path.addCurve(to: p2, control1: cp1, control2: cp2)
        }
    }
}

// MARK: - Synchronized Stock Row Price Section View

struct StockRowPriceSectionView: View {
    let ticker: String
    let quote: StockQuote

    @State private var service = Stock24hDataService.shared

    var body: some View {
        let stats = service.stats(for: ticker, quote: quote)

        HStack(spacing: 8) {
            // 24h Mini Chart
            Stock24hMiniChartView(
                ticker: ticker,
                quote: quote,
                stats: stats
            )
            .frame(width: 58, height: 26)

            // Price & 24h Change Badge (matches StockDetailView exactly)
            VStack(alignment: .trailing, spacing: 3) {
                Text(quote.formattedPrice)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.black)

                let isPositive = stats.isPositive
                let sign = isPositive ? "+" : "-"
                Text(String(format: "%@%.2f%%", sign, abs(stats.changePercent)))
                    .font(.caption2.bold())
                    .foregroundStyle(isPositive ? Color(hex: "00B89F") : Color(hex: "FF3B30"))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        (isPositive ? Color(hex: "00B89F") : Color(hex: "FF3B30")).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 4)
                    )
            }
        }
        .task(id: ticker) {
            await service.load24hData(ticker: ticker, quote: quote)
        }
    }
}

// MARK: - Color Extension Helper

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
