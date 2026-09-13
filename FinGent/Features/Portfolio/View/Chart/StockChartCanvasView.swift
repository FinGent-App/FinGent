// Features/Portfolio/View/Chart/StockChartCanvasView.swift

import SwiftUI

// MARK: - MorphPoint (VectorArithmetic for chart morphing)

struct MorphPoint: VectorArithmetic, Sendable {
    var x: CGFloat
    var y: CGFloat

    static var zero: MorphPoint { .init(x: 0, y: 0) }

    static func + (lhs: Self, rhs: Self) -> Self { .init(x: lhs.x + rhs.x, y: lhs.y + rhs.y) }
    static func - (lhs: Self, rhs: Self) -> Self { .init(x: lhs.x - rhs.x, y: lhs.y - rhs.y) }

    mutating func scale(by rhs: Double) { x *= CGFloat(rhs); y *= CGFloat(rhs) }

    var magnitudeSquared: Double { Double(x * x + y * y) }
}

// MARK: - AnimatableChartData

struct AnimatableChartData: VectorArithmetic, Equatable, Sendable {

    var points: [MorphPoint]

    static var zero: Self { .init(points: []) }

    static func + (lhs: Self, rhs: Self) -> Self {
        let n = max(lhs.points.count, rhs.points.count)
        let lp = lhs.padded(to: n); let rp = rhs.padded(to: n)
        var result: [MorphPoint] = []; result.reserveCapacity(n)
        for i in 0..<n { result.append(lp[i] + rp[i]) }
        return .init(points: result)
    }

    static func - (lhs: Self, rhs: Self) -> Self {
        let n = max(lhs.points.count, rhs.points.count)
        let lp = lhs.padded(to: n); let rp = rhs.padded(to: n)
        var result: [MorphPoint] = []; result.reserveCapacity(n)
        for i in 0..<n { result.append(lp[i] - rp[i]) }
        return .init(points: result)
    }

    mutating func scale(by rhs: Double) { for i in points.indices { points[i].scale(by: rhs) } }

    var magnitudeSquared: Double { points.reduce(0) { $0 + $1.magnitudeSquared } }

    private func padded(to count: Int) -> [MorphPoint] {
        guard let last = points.last else { return Array(repeating: .zero, count: count) }
        if points.count >= count { return points }
        return points + Array(repeating: last, count: count - points.count)
    }
}

// MARK: - Chart Canvas View

struct StockChartCanvasView<VM: ChartViewModelProtocol>: View {

    @ObservedObject var chartVM: VM
    @Binding var selectedPoint: StockHistoryPoint?
    @Binding var isDragging: Bool
    @Binding var chartSize: CGSize

    let accentColor: Color
    let displayIsPositive: Bool
    var isUSD: Bool = false
    var fixedColor: Color? = nil
    var showAreaGradient: Bool = true
    var lineWidth: CGFloat = 1.6
    var containerBackgroundColor: Color? = Color.white.opacity(0.04)

    @State private var animatedData: AnimatableChartData = .zero
    @State private var oneDayReady: Bool = false
    @State private var oneDayClipWidth: CGFloat = 0
    @State private var oneDayRevealDone: Bool = false
    @State private var hasEverLoadedOneDay: Bool = false
    @State private var pulseScale: CGFloat = 1.0
    @State private var animatedBaselineY: CGFloat = 0

    private let resampleCount = 300

    private var greenColor: Color { fixedColor ?? Color(red: 0.0, green: 0.831, blue: 0.667) }
    private var redColor: Color   { fixedColor ?? Color(red: 0.937, green: 0.267, blue: 0.267) }
    private var goldColor: Color  { Color(red: 234/255, green: 179/255, blue: 8/255) }

    // MARK: - Market Active Detection

    private var isMarketActive: Bool {
        guard let firstPoint = chartVM.dataPoints.first else { return false }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        let now = Date()

        let weekday = cal.component(.weekday, from: now)
        guard weekday >= 2 && weekday <= 6 else { return false }

        let openHour = cal.component(.hour, from: firstPoint.date)
        let isUSStock = isUSD || openHour >= 19 || openHour < 5

        let nowH = cal.component(.hour, from: now)
        let nowM = cal.component(.minute, from: now)
        let nowMins = nowH * 60 + nowM

        if isUSStock {
            return nowMins >= 20 * 60 || nowMins <= 5 * 60 + 30
        } else {
            return IDXTradingCalendar.isSessionOpen(now)
        }
    }

    var body: some View {
        coreChart
            .gesture(dragGesture)
            .onChange(of: chartVM.isLoading) { _, isLoading in
                guard !isLoading else { return }
                applyChartData()
            }
            .onChange(of: chartSize) { _, newSize in
                guard newSize.width > 0, !chartVM.dataPoints.isEmpty, animatedData.points.isEmpty else { return }
                applyChartData()
            }
            .onChange(of: chartVM.dataPoints) { _, _ in
                guard chartSize.width > 0 else { return }
                applyChartData()
                updatePulse()
            }
            .onAppear {
                updatePulse()
            }
            .onChange(of: chartVM.selectedRange) { _, _ in
                updatePulse()
            }
    }

    private var coreChart: some View {
        ZStack {
            let shouldShow = chartSize.height > 0 && (oneDayReady || !animatedData.points.isEmpty)

            if shouldShow {
                chartContent
            } else if chartVM.dataPoints.isEmpty && !chartVM.isLoading {
                Text("Data historis belum tersedia")
                    .font(.caption).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if chartVM.isLoading {
                ProgressView()
                    .tint(.teal)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .background(
            Group {
                if let bg = containerBackgroundColor, bg != .clear {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(bg)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                }
            }
        )
        .contentShape(Rectangle().inset(by: -40))
    }

    // MARK: - Pulse Animation

    private func updatePulse() {
        guard chartVM.selectedRange == .oneDay, isMarketActive else {
            pulseScale = 1.0
            return
        }
        pulseScale = 1.0
        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
            pulseScale = 2.4
        }
    }

    // MARK: - Apply Data Morphing

    private func applyChartData() {
        guard !chartVM.dataPoints.isEmpty, chartSize.width > 0 else { return }

        if chartVM.selectedRange == .oneDay {
            if hasEverLoadedOneDay && oneDayReady { return }

            let oneDayTarget = buildMorphPoints(chartVM.dataPoints, range: chartVM.selectedRange, size: chartSize)
            let lastSlotIdx  = chartVM.oneDaySlotIndex(for: chartVM.dataPoints.last!.date)
            let innerW       = chartSize.width - 8
            let xLast        = 4 + CGFloat(lastSlotIdx) / CGFloat(max(chartVM.oneDayTotalSlots - 1, 1)) * innerW
            let targetClip   = min(xLast + 4, chartSize.width)

            if !hasEverLoadedOneDay {
                animatedData        = oneDayTarget
                hasEverLoadedOneDay = true
                oneDayReady         = true
                oneDayClipWidth     = 0
                oneDayRevealDone    = false
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 1.2)) { oneDayClipWidth = targetClip }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) { oneDayRevealDone = true }
                }
            } else {
                oneDayReady = false
                withAnimation(.spring(response: 1.2, dampingFraction: 1.0)) { animatedData = oneDayTarget }
            }
        } else {
            oneDayReady = false
            let target = buildMorphPoints(chartVM.dataPoints, range: chartVM.selectedRange, size: chartSize)

            if animatedData.points.isEmpty {
                animatedData = AnimatableChartData(points: (0..<resampleCount).map { i in
                    let t = CGFloat(i) / CGFloat(resampleCount - 1)
                    return MorphPoint(x: t * chartSize.width, y: chartSize.height / 2)
                })
            }
            let targetBaselineY = yPos(for: chartVM.startPrice, in: chartSize)
            withAnimation(.spring(response: 1.55, dampingFraction: 1.0)) {
                animatedData      = target
                animatedBaselineY = targetBaselineY
            }
        }
    }

    // MARK: - Chart Content

    @ViewBuilder
    private var chartContent: some View {
        let data    = chartVM.dataPoints
        let minP    = chartVM.minPrice
        let maxP    = chartVM.maxPrice
        let startP  = chartVM.startPrice
        let lastP   = chartVM.latestPrice
        let isOneDay = chartVM.selectedRange == .oneDay && oneDayReady

        let yMax      = yPos(for: maxP,   in: chartSize)
        let yMin      = yPos(for: minP,   in: chartSize)
        let yBaseline = yPos(for: startP, in: chartSize)
        let yLast     = yPos(for: lastP,  in: chartSize)

        let oneDayPoints: [OneDayLineShape.Point] = isOneDay ? {
            let closes = data.map(\.close)
            let minV   = closes.min() ?? minP
            let maxV   = closes.max() ?? maxP
            let range  = maxV - minV
            return data.map { pt in
                OneDayLineShape.Point(
                    slotIndex: chartVM.oneDaySlotIndex(for: pt.date),
                    normY: range > 0 ? (pt.close - minV) / range : 0.5
                )
            }
        }() : []

        ZStack {
            // ==== Grafik clipped rounded ====
            ZStack {
                DashLine(from: CGPoint(x: 0, y: yMax), to: CGPoint(x: chartSize.width, y: yMax))
                    .stroke(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                DashLine(from: CGPoint(x: 0, y: yMin), to: CGPoint(x: chartSize.width, y: yMin))
                    .stroke(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                AnimatableHDashLine(y: yBaseline)
                    .stroke(goldColor.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                    .animation(.spring(response: 1.55, dampingFraction: 1.0), value: yBaseline)

                if isOneDay {
                    ZStack {
                        if showAreaGradient {
                            OneDayAreaShape(points: oneDayPoints, totalSlots: chartVM.oneDayTotalSlots,
                                            hPad: 4, closingY: yBaseline)
                                .fill(LinearGradient(stops: [
                                    .init(color: greenColor.opacity(0.38), location: 0.0),
                                    .init(color: greenColor.opacity(0.18), location: 0.5),
                                    .init(color: greenColor.opacity(0.0),  location: 1.0)],
                                    startPoint: .top, endPoint: .bottom))
                                .clipShape(Rectangle().path(in: CGRect(x: 0, y: 0, width: chartSize.width, height: yBaseline)))
                            OneDayAreaShape(points: oneDayPoints, totalSlots: chartVM.oneDayTotalSlots,
                                            hPad: 4, closingY: yBaseline)
                                .fill(LinearGradient(stops: [
                                    .init(color: redColor.opacity(0.38), location: 0.0),
                                    .init(color: redColor.opacity(0.18), location: 0.5),
                                    .init(color: redColor.opacity(0.0),  location: 1.0)],
                                    startPoint: .bottom, endPoint: .top))
                                .clipShape(Rectangle().path(in: CGRect(x: 0, y: yBaseline,
                                    width: chartSize.width, height: chartSize.height - yBaseline)))
                        }

                        if fixedColor != nil {
                            OneDayLineShape(points: oneDayPoints, totalSlots: chartVM.oneDayTotalSlots, hPad: 4)
                                .stroke(greenColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                        } else {
                            OneDayLineShape(points: oneDayPoints, totalSlots: chartVM.oneDayTotalSlots, hPad: 4)
                                .stroke(greenColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                                .clipShape(Rectangle().path(in: CGRect(x: 0, y: 0, width: chartSize.width, height: yBaseline)))
                            OneDayLineShape(points: oneDayPoints, totalSlots: chartVM.oneDayTotalSlots, hPad: 4)
                                .stroke(redColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                                .clipShape(Rectangle().path(in: CGRect(x: 0, y: yBaseline,
                                    width: chartSize.width, height: chartSize.height - yBaseline)))
                        }
                    }
                    .clipShape(AnimatableClipRect(clipWidth: oneDayClipWidth))

                } else {
                    ZStack {
                        if showAreaGradient {
                            MorphingXYAreaShape(data: animatedData, closingY: animatedBaselineY)
                                .fill(LinearGradient(stops: [
                                    .init(color: greenColor.opacity(0.38), location: 0.0),
                                    .init(color: greenColor.opacity(0.18), location: 0.5),
                                    .init(color: greenColor.opacity(0.0),  location: 1.0)],
                                    startPoint: .top, endPoint: .bottom))
                                .clipShape(AnimatableClipAbove(cutY: animatedBaselineY))
                            MorphingXYAreaShape(data: animatedData, closingY: animatedBaselineY)
                                .fill(LinearGradient(stops: [
                                    .init(color: redColor.opacity(0.38), location: 0.0),
                                    .init(color: redColor.opacity(0.18), location: 0.5),
                                    .init(color: redColor.opacity(0.0),  location: 1.0)],
                                    startPoint: .bottom, endPoint: .top))
                                .clipShape(AnimatableClipBelow(cutY: animatedBaselineY, totalHeight: chartSize.height))
                        }

                        if fixedColor != nil {
                            MorphingXYLineShape(data: animatedData)
                                .stroke(greenColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                        } else {
                            MorphingXYLineShape(data: animatedData)
                                .stroke(greenColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                                .clipShape(AnimatableClipAbove(cutY: animatedBaselineY))
                            MorphingXYLineShape(data: animatedData)
                                .stroke(redColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                                .clipShape(AnimatableClipBelow(cutY: animatedBaselineY, totalHeight: chartSize.height))
                        }
                    }
                    .clipShape(AnimatableClipRect(clipWidth: chartSize.width))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))

            // ==== Overlay: Max/Min Labels, Dot, Crosshair ====

            // Max / Min Labels
            Text("Max \(formatDisplayPrice(maxP))")
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .foregroundColor(Color.black.opacity(0.65))
                .padding(.horizontal, 5)
                .padding(.vertical, 2.5)
                .background(Color.white.opacity(0.75))
                .cornerRadius(5)
                .position(x: chartSize.width - 40, y: max(yMax - 12, 14))

            Text("Min \(formatDisplayPrice(minP))")
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .foregroundColor(Color.black.opacity(0.65))
                .padding(.horizontal, 5)
                .padding(.vertical, 2.5)
                .background(Color.white.opacity(0.75))
                .cornerRadius(5)
                .position(x: chartSize.width - 40, y: min(yMin + 12, chartSize.height - 14))

            // Active price dot & dashed line — 1D
            if isOneDay && !isDragging {
                let innerW   = chartSize.width - 8
                let dotColor = lastP >= startP ? greenColor : redColor

                if !oneDayRevealDone && data.count > 1 {
                    let tipPoints: [CGPoint] = data.map { pt in
                        let slot = chartVM.oneDaySlotIndex(for: pt.date)
                        return CGPoint(
                            x: 4 + CGFloat(slot) / CGFloat(max(chartVM.oneDayTotalSlots - 1, 1)) * innerW,
                            y: yPos(for: pt.close, in: chartSize)
                        )
                    }
                    ZStack {
                        Circle().fill(dotColor).frame(width: 9, height: 9)
                            .shadow(color: dotColor.opacity(0.7), radius: 5)
                        Circle().fill(Color.white).frame(width: 4, height: 4)
                    }
                    .frame(width: 9, height: 9)
                    .position(x: 0, y: 0)
                    .modifier(GrowingLineTip(tipX: oneDayClipWidth, points: tipPoints))
                } else {
                    let lastSlotIdx = data.isEmpty ? 0 : chartVM.oneDaySlotIndex(for: data.last!.date)
                    let dotX        = 4 + CGFloat(lastSlotIdx) / CGFloat(max(chartVM.oneDayTotalSlots - 1, 1)) * innerW

                    AnimatableHDashLine(y: yLast)
                        .stroke(dotColor.opacity(0.70), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))

                    if isMarketActive {
                        Circle()
                            .fill(dotColor.opacity(0.25))
                            .frame(width: 9 * pulseScale, height: 9 * pulseScale)
                            .position(x: dotX, y: yLast)
                    }
                    Circle().fill(dotColor).frame(width: 9, height: 9)
                        .shadow(color: dotColor.opacity(0.7), radius: 5)
                        .position(x: dotX, y: yLast)
                    Circle().fill(Color.white).frame(width: 4, height: 4)
                        .position(x: dotX, y: yLast)
                }
            }

            // Last price dot & dashed line — non-1D
            if !isDragging && !isOneDay {
                let dotColor  = lastP >= startP ? greenColor : redColor
                let animX = animatedData.points.last.map { $0.x } ?? xFor(index: data.count - 1, count: data.count, width: chartSize.width)
                let animY = animatedData.points.last.map { $0.y } ?? yLast

                AnimatableHDashLine(y: animY)
                    .stroke(dotColor.opacity(0.70), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                    .animation(.spring(response: 1.55, dampingFraction: 1.0), value: animY)
                Circle().fill(dotColor).frame(width: 9, height: 9)
                    .shadow(color: dotColor.opacity(0.7), radius: 5)
                    .position(x: animX, y: animY)
                Circle().fill(Color.white).frame(width: 4, height: 4)
                    .position(x: animX, y: animY)
            }

            // Crosshair
            if isDragging, let point = selectedPoint {
                let ptColor = point.close >= startP ? greenColor : redColor
                CrosshairView(
                    point:       point,
                    chartVM:     chartVM,
                    chartSize:   chartSize,
                    accentColor: ptColor,
                    xPos: xFor(index: data.firstIndex(where: { $0.id == point.id }) ?? 0,
                               count: data.count, width: chartSize.width),
                    yPos: yPos(for: point.close, in: chartSize)
                )
            }
        }
    }

    private func formatDisplayPrice(_ value: Double) -> String {
        if isUSD {
            return String(format: "$%.2f", value)
        } else {
            return "Rp \(NumberFormatters.stockPrice(value))"
        }
    }

    // MARK: - Drag Gesture

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { val in
                isDragging = true
                let data = chartVM.dataPoints
                guard !data.isEmpty, chartSize.width > 0 else { return }

                let innerWidth = chartSize.width - 8
                let clampedX   = max(0, min(val.location.x - 4, innerWidth))
                let nearest: StockHistoryPoint

                if chartVM.selectedRange == .oneDay {
                    let totalSlots = chartVM.oneDayTotalSlots
                    let slotFrac   = clampedX / innerWidth * CGFloat(max(totalSlots - 1, 1))
                    let targetSlot = Int(slotFrac.rounded())
                    nearest = data.min(by: {
                        abs(chartVM.oneDaySlotIndex(for: $0.date) - targetSlot) <
                        abs(chartVM.oneDaySlotIndex(for: $1.date) - targetSlot)
                    }) ?? data[0]
                } else {
                    let touchX = clampedX + 4
                    if !animatedData.points.isEmpty {
                        let bestMorphIdx = animatedData.points.indices.min(by: {
                            abs(animatedData.points[$0].x - touchX) <
                            abs(animatedData.points[$1].x - touchX)
                        }) ?? 0
                        let dataFrac = CGFloat(bestMorphIdx) / CGFloat(max(animatedData.points.count - 1, 1))
                        let i = max(0, min(Int((dataFrac * CGFloat(data.count - 1)).rounded()), data.count - 1))
                        nearest = data[i]
                    } else {
                        let i = max(0, min(Int((clampedX / innerWidth * CGFloat(data.count - 1)).rounded()), data.count - 1))
                        nearest = data[i]
                    }
                }

                if nearest.id != selectedPoint?.id {
                    selectedPoint = nearest
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
            .onEnded { _ in
                withAnimation(.easeOut(duration: 0.25)) {
                    isDragging    = false
                    selectedPoint = nil
                }
            }
    }

    // MARK: - Build MorphPoints with Catmull-Rom Spline

    private func buildMorphPoints(_ data: [StockHistoryPoint], range: TimeRange, size: CGSize) -> AnimatableChartData {
        guard data.count > 1, size.width > 0, size.height > 0 else { return .zero }

        let closes = data.map(\.close)
        let minV   = closes.min()!; let maxV = closes.max()!; let vRange = maxV - minV
        let topPad: CGFloat = 20; let bottomPad: CGFloat = 20; let hPad: CGFloat = 4
        let usable = size.height - topPad - bottomPad
        let innerW = size.width - hPad * 2

        if range == .oneDay {
            let totalSlots  = chartVM.oneDayTotalSlots
            let lastSlotIdx = chartVM.oneDaySlotIndex(for: data.last!.date)
            var morphPoints: [MorphPoint] = []; morphPoints.reserveCapacity(resampleCount)

            for i in 0..<resampleCount {
                let slotFrac = CGFloat(i) / CGFloat(resampleCount - 1) * CGFloat(max(totalSlots - 1, 1))
                let slot     = Int(slotFrac)
                let x: CGFloat; let y: CGFloat

                if slot <= lastSlotIdx {
                    let activeFrac = CGFloat(lastSlotIdx) / CGFloat(max(totalSlots - 1, 1))
                    let dataFrac   = (slotFrac / CGFloat(max(totalSlots - 1, 1))) / max(activeFrac, 1e-6) * CGFloat(data.count - 1)
                    let lo   = max(0, min(Int(dataFrac), data.count - 1))
                    let hi   = min(lo + 1, data.count - 1)
                    let frac = dataFrac - CGFloat(lo)
                    let val  = closes[lo] * Double(1 - frac) + closes[hi] * Double(frac)
                    let normY = vRange > 0 ? (val - minV) / vRange : 0.5
                    y = topPad + usable * CGFloat(1.0 - normY)
                    x = hPad + slotFrac / CGFloat(max(totalSlots - 1, 1)) * innerW
                } else {
                    let normY = vRange > 0 ? (closes.last! - minV) / vRange : 0.5
                    y = topPad + usable * CGFloat(1.0 - normY)
                    x = hPad + CGFloat(lastSlotIdx) / CGFloat(max(totalSlots - 1, 1)) * innerW
                }
                morphPoints.append(MorphPoint(x: x, y: y))
            }
            return AnimatableChartData(points: morphPoints)
        } else {
            let exponent = range.xSpacingExponent
            let points: [MorphPoint] = (0..<resampleCount).map { i in
                let tData = Double(i) / Double(resampleCount - 1) * Double(data.count - 1)
                let lo    = max(0, min(Int(tData), data.count - 1))
                let hi    = min(lo + 1, data.count - 1)
                let frac  = tData - Double(lo)

                // Catmull-Rom cubic spline interpolation
                let p0Val = closes[max(lo - 1, 0)]
                let p1Val = closes[lo]
                let p2Val = closes[hi]
                let p3Val = closes[min(hi + 1, closes.count - 1)]
                let t2    = frac * frac
                let t3    = t2 * frac
                let val   = 0.5 * (
                    (2.0 * p1Val) +
                    (-p0Val + p2Val) * frac +
                    (2.0 * p0Val - 5.0 * p1Val + 4.0 * p2Val - p3Val) * t2 +
                    (-p0Val + 3.0 * p1Val - 3.0 * p2Val + p3Val) * t3
                )

                let normY = vRange > 0 ? (val - minV) / vRange : 0.5
                let y     = topPad + usable * CGFloat(1.0 - normY)
                let t     = CGFloat(i) / CGFloat(resampleCount - 1)
                let x     = hPad + pow(t, exponent) * innerW
                return MorphPoint(x: x, y: y)
            }
            return AnimatableChartData(points: points)
        }
    }

    // MARK: - Coordinate Helpers

    private func xFor(index: Int, count: Int, width: CGFloat) -> CGFloat {
        let innerWidth = width - 8
        if chartVM.selectedRange == .oneDay {
            let data = chartVM.dataPoints
            guard index < data.count else { return 4 + CGFloat(index) / CGFloat(max(count - 1, 1)) * innerWidth }
            let slotIdx = chartVM.oneDaySlotIndex(for: data[index].date)
            return 4 + CGFloat(slotIdx) / CGFloat(max(chartVM.oneDayTotalSlots - 1, 1)) * innerWidth
        }
        guard !animatedData.points.isEmpty else { return 4 + CGFloat(index) / CGFloat(max(count - 1, 1)) * innerWidth }
        let fraction = CGFloat(index) / CGFloat(max(count - 1, 1))
        let ptIndex  = min(max(Int((fraction * CGFloat(animatedData.points.count - 1)).rounded()), 0), animatedData.points.count - 1)
        return animatedData.points[ptIndex].x
    }

    private func yPos(for value: Double, in size: CGSize) -> CGFloat {
        let topPad: CGFloat = 20; let bottomPad: CGFloat = 20
        let usable = size.height - topPad - bottomPad
        guard usable > 0 else { return size.height / 2 }
        let range = chartVM.maxPrice - chartVM.minPrice
        let norm  = range > 0 ? (value - chartVM.minPrice) / range : 0.5
        return topPad + usable * (1 - norm)
    }
}

// MARK: - Shapes

struct DashLine: Shape {
    let from: CGPoint; let to: CGPoint
    func path(in rect: CGRect) -> Path {
        var p = Path(); p.move(to: from); p.addLine(to: to); return p
    }
}

struct AnimatableHDashLine: Shape {
    var y: CGFloat
    var animatableData: CGFloat { get { y } set { y = newValue } }
    func path(in rect: CGRect) -> Path {
        var p = Path(); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: rect.width, y: y)); return p
    }
}

struct OneDayLineShape: Shape {
    struct Point { let slotIndex: Int; let normY: Double }
    var points: [Point]; var totalSlots: Int; var hPad: CGFloat

    func path(in rect: CGRect) -> Path {
        guard points.count > 1 else { return Path() }
        let topPad: CGFloat = 20; let bottomPad: CGFloat = 20
        let usable = rect.height - topPad - bottomPad
        let innerWidth = rect.width - hPad * 2
        guard usable > 0, innerWidth > 0 else { return Path() }
        func cgPoint(_ p: Point) -> CGPoint {
            CGPoint(x: hPad + CGFloat(p.slotIndex) / CGFloat(max(totalSlots - 1, 1)) * innerWidth,
                    y: topPad + usable * CGFloat(1.0 - p.normY))
        }
        var path = Path(); path.move(to: cgPoint(points[0]))
        for i in 1..<points.count { path.addLine(to: cgPoint(points[i])) }
        return path
    }
}

struct OneDayAreaShape: Shape {
    var points: [OneDayLineShape.Point]; var totalSlots: Int; var hPad: CGFloat; var closingY: CGFloat

    func path(in rect: CGRect) -> Path {
        guard points.count > 1 else { return Path() }
        let topPad: CGFloat = 20; let bottomPad: CGFloat = 20
        let usable = rect.height - topPad - bottomPad
        let innerWidth = rect.width - hPad * 2
        guard usable > 0, innerWidth > 0 else { return Path() }
        func cgPoint(_ p: OneDayLineShape.Point) -> CGPoint {
            CGPoint(x: hPad + CGFloat(p.slotIndex) / CGFloat(max(totalSlots - 1, 1)) * innerWidth,
                    y: topPad + usable * CGFloat(1.0 - p.normY))
        }
        var path = Path(); path.move(to: cgPoint(points[0]))
        for i in 1..<points.count { path.addLine(to: cgPoint(points[i])) }
        let lastX  = hPad + CGFloat(points.last!.slotIndex)  / CGFloat(max(totalSlots - 1, 1)) * innerWidth
        let firstX = hPad + CGFloat(points.first!.slotIndex) / CGFloat(max(totalSlots - 1, 1)) * innerWidth
        path.addLine(to: CGPoint(x: lastX,  y: closingY))
        path.addLine(to: CGPoint(x: firstX, y: closingY))
        path.closeSubpath()
        return path
    }
}

struct MorphingXYLineShape: Shape {
    var data: AnimatableChartData
    var animatableData: AnimatableChartData { get { data } set { data = newValue } }

    func path(in rect: CGRect) -> Path {
        let pts = data.points; guard pts.count > 1 else { return Path() }
        var path = Path(); path.move(to: CGPoint(x: pts[0].x, y: pts[0].y))
        for i in 1..<pts.count {
            path.addLine(to: CGPoint(x: pts[i].x, y: pts[i].y))
        }
        return path
    }
}

struct MorphingXYAreaShape: Shape {
    var data: AnimatableChartData; var closingY: CGFloat
    var animatableData: AnimatablePair<AnimatableChartData, CGFloat> {
        get { AnimatablePair(data, closingY) }
        set { data = newValue.first; closingY = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let pts = data.points; guard pts.count > 1 else { return Path() }
        var path = Path(); path.move(to: CGPoint(x: pts[0].x, y: pts[0].y))
        for i in 1..<pts.count {
            path.addLine(to: CGPoint(x: pts[i].x, y: pts[i].y))
        }
        path.addLine(to: CGPoint(x: pts.last!.x,  y: closingY))
        path.addLine(to: CGPoint(x: pts.first!.x, y: closingY))
        path.closeSubpath()
        return path
    }
}

struct AnimatableClipRect: Shape {
    var clipWidth: CGFloat
    var animatableData: CGFloat { get { clipWidth } set { clipWidth = newValue } }
    func path(in rect: CGRect) -> Path { Path(CGRect(x: 0, y: 0, width: max(0, clipWidth), height: rect.height)) }
}

struct AnimatableClipAbove: Shape {
    var cutY: CGFloat
    var animatableData: CGFloat { get { cutY } set { cutY = newValue } }
    func path(in rect: CGRect) -> Path { Path(CGRect(x: 0, y: 0, width: rect.width, height: max(0, cutY))) }
}

struct AnimatableClipBelow: Shape {
    var cutY: CGFloat; var totalHeight: CGFloat
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(cutY, totalHeight) }
        set { cutY = newValue.first; totalHeight = newValue.second }
    }
    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: 0, y: cutY, width: rect.width, height: max(0, totalHeight - cutY)))
    }
}

struct GrowingLineTip: GeometryEffect {
    var tipX: CGFloat
    let points: [CGPoint]

    var animatableData: CGFloat {
        get { tipX }
        set { tipX = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        guard let first = points.first, let last = points.last else {
            return ProjectionTransform()
        }
        let x = min(max(tipX, first.x), last.x)
        let y = interpolatedY(atX: x)
        return ProjectionTransform(CGAffineTransform(translationX: x, y: y))
    }

    private func interpolatedY(atX x: CGFloat) -> CGFloat {
        guard let first = points.first, let last = points.last else { return 0 }
        if x <= first.x { return first.y }
        if x >= last.x  { return last.y }
        for i in 1..<points.count where points[i].x >= x {
            let p0 = points[i - 1], p1 = points[i]
            let dx = p1.x - p0.x
            let t  = dx == 0 ? 0 : (x - p0.x) / dx
            return p0.y + (p1.y - p0.y) * t
        }
        return last.y
    }
}

// MARK: - Crosshair & Tooltip

struct CrosshairView<VM: ChartViewModelProtocol>: View {
    let point: StockHistoryPoint
    let chartVM: VM
    let chartSize: CGSize
    let accentColor: Color
    let xPos: CGFloat
    let yPos: CGFloat

    var body: some View {
        ZStack {
            DashLine(from: CGPoint(x: 0, y: yPos), to: CGPoint(x: chartSize.width, y: yPos))
                .stroke(accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
            DashLine(from: CGPoint(x: xPos, y: 0), to: CGPoint(x: xPos, y: chartSize.height))
                .stroke(Color.black.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            Circle().fill(accentColor).frame(width: 13, height: 13)
                .shadow(color: accentColor.opacity(0.7), radius: 6).position(x: xPos, y: yPos)
            Circle().fill(Color.white).frame(width: 5, height: 5).position(x: xPos, y: yPos)
            TooltipView(date: point.date, range: chartVM.selectedRange, xPos: xPos, chartWidth: chartSize.width)
        }
    }
}

struct TooltipView: View {
    let date: Date
    let range: TimeRange
    let xPos: CGFloat
    let chartWidth: CGFloat

    private let h: CGFloat = 26; private let pad: CGFloat = 6

    private var text: String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "id_ID")
        df.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        df.dateFormat = range.isIntraday ? "d MMM 'pukul' HH:mm" : "d MMM yyyy"
        return df.string(from: date)
    }

    private var estimatedWidth: CGFloat { CGFloat(text.count) * 7.5 + 20 }

    private var clampedX: CGFloat {
        var x = xPos - estimatedWidth / 2
        x = max(pad, min(x, chartWidth - estimatedWidth - pad))
        return x + estimatedWidth / 2
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundColor(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(height: h)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.systemBackground).opacity(0.95))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                    .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
            )
            .position(x: clampedX, y: h / 2 + 6)
            .transition(.opacity)
    }
}
