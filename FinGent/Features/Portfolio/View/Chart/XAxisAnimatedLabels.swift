// Features/Portfolio/View/Chart/XAxisAnimatedLabels.swift

import SwiftUI

// MARK: - Axis Tick Model

struct AxisTick: Identifiable, Equatable {
    let id:    Int
    let normX: Double
    let label: String
}

// MARK: - Axis Tick Generator

enum AxisTickGenerator {

    private static var jakartaCal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        return c
    }()

    static func ticks<VM: ChartViewModelProtocol>(for data: [StockHistoryPoint], range: TimeRange, chartVM: VM) -> [AxisTick] {
        guard !data.isEmpty else { return [] }
        switch range {
        case .oneDay:     return oneDayTicks(data: data, chartVM: chartVM)
        case .oneWeek:    return oneWeekTicks(data: data)
        case .oneMonth:   return oneMonthTicks(data: data)
        case .threeMonth: return threeMonthTicks(data: data)
        case .ytd:        return ytdTicks(data: data)
        case .oneYear:    return oneYearTicks(data: data)
        case .fiveYear:   return fiveYearTicks(data: data)
        case .all:        return fiveYearTicks(data: data)
        }
    }

    private static func firstIndexPerDay(_ data: [StockHistoryPoint]) -> [(index: Int, date: Date)] {
        var seen = Set<String>(); var result: [(Int, Date)] = []
        let df = DateFormatter(); df.timeZone = TimeZone(identifier: "Asia/Jakarta")!; df.dateFormat = "yyyy-MM-dd"
        for (i, pt) in data.enumerated() {
            let key = df.string(from: pt.date)
            if !seen.contains(key) { seen.insert(key); result.append((i, pt.date)) }
        }
        return result
    }

    private static func firstIndexPerMonth(_ data: [StockHistoryPoint]) -> [(key: String, index: Int, date: Date)] {
        var buckets: [String: (Int, Date)] = [:]
        let df = DateFormatter(); df.timeZone = TimeZone(identifier: "Asia/Jakarta")!; df.dateFormat = "yyyy-MM"
        for (i, pt) in data.enumerated() {
            let key = df.string(from: pt.date)
            if buckets[key] == nil { buckets[key] = (i, pt.date) }
        }
        return buckets.keys.sorted().compactMap { k in buckets[k].map { (k, $0.0, $0.1) } }
    }

    private static func nearestIndex(in data: [StockHistoryPoint], to targetDate: Date) -> Int? {
        data.enumerated().min(by: {
            abs($0.element.date.timeIntervalSince(targetDate)) < abs($1.element.date.timeIntervalSince(targetDate))
        })?.offset
    }

    private static func oneDayTicks<VM: ChartViewModelProtocol>(data: [StockHistoryPoint], chartVM: VM) -> [AxisTick] {
        guard let firstDate = data.first?.date else { return [] }
        let weekday    = jakartaCal.component(.weekday, from: firstDate)
        let totalSlots = chartVM.oneDayTotalSlots
        let openMins   = chartVM.oneDayOpenMinutes
        let lastSlotIndex: Int = {
            guard let lastPt = data.last else { return 0 }
            let h = jakartaCal.component(.hour, from: lastPt.date)
            let m = jakartaCal.component(.minute, from: lastPt.date)
            let mins = (h * 60 + m) - openMins
            return max(0, min(mins / 5, totalSlots - 1))
        }()

        let candidates: [(hour: Int, minute: Int, label: String)] = weekday == 6
            ? [(9,30,"09:30"),(10,30,"10:30"),(11,30,"11:30"),(14,0,"14:00"),(15,0,"15:00")]
            : [(10,0,"10:00"),(11,0,"11:00"),(12,0,"12:00"),(13,30,"13:30"),(14,30,"14:30"),(15,30,"15:30")]
        var result: [AxisTick] = []; var ordinal = 0
        for slot in candidates {
            let slotIndex = (slot.hour * 60 + slot.minute - openMins) / 5
            guard slotIndex >= 0, slotIndex <= lastSlotIndex else { continue }
            result.append(AxisTick(id: ordinal, normX: Double(slotIndex) / Double(max(totalSlots - 1, 1)), label: slot.label))
            ordinal += 1
        }
        return result
    }

    private static func oneWeekTicks(data: [StockHistoryPoint]) -> [AxisTick] {
        let days = firstIndexPerDay(data); let total = max(data.count - 1, 1); let cal = jakartaCal
        let dayDF = DateFormatter(); dayDF.timeZone = TimeZone(identifier: "Asia/Jakarta")!; dayDF.dateFormat = "d"
        let monDF = DateFormatter(); monDF.locale = Locale(identifier: "id_ID")
        monDF.timeZone = TimeZone(identifier: "Asia/Jakarta")!; monDF.dateFormat = "MMM"
        var ticks: [AxisTick] = []; var prevMonth = -1
        for (ordinal, pair) in days.enumerated() {
            let month = cal.component(.month, from: pair.date)
            let isNewMonth = (prevMonth != -1 && month != prevMonth)
            let label = isNewMonth ? monDF.string(from: pair.date) : dayDF.string(from: pair.date)
            ticks.append(AxisTick(id: ordinal, normX: Double(pair.index) / Double(total), label: label))
            prevMonth = month
        }
        return ticks
    }

    private static func oneMonthTicks(data: [StockHistoryPoint]) -> [AxisTick] {
        let days = firstIndexPerDay(data); let total = max(data.count - 1, 1); let cal = jakartaCal
        let dayDF = DateFormatter(); dayDF.timeZone = TimeZone(identifier: "Asia/Jakarta")!; dayDF.dateFormat = "d"
        let monDF = DateFormatter(); monDF.locale = Locale(identifier: "id_ID")
        monDF.timeZone = TimeZone(identifier: "Asia/Jakarta")!; monDF.dateFormat = "MMM"
        var prevMonth = -1; var isNewMonthDay = [Bool]()
        for pair in days {
            let m = cal.component(.month, from: pair.date)
            isNewMonthDay.append(prevMonth != -1 && m != prevMonth); prevMonth = m
        }
        let maxLabels = min(5, days.count); var selectedIndices = Set<Int>()
        if days.count <= maxLabels { days.indices.forEach { selectedIndices.insert($0) } }
        else {
            let step = Double(days.count - 1) / Double(maxLabels - 1)
            for k in 0..<maxLabels { selectedIndices.insert(min(Int(Double(k) * step + 0.5), days.count - 1)) }
        }
        for (k, isNew) in isNewMonthDay.enumerated() { if isNew { selectedIndices.insert(k) } }
        let newMonthPositions = isNewMonthDay.indices.filter { isNewMonthDay[$0] }; let minGap = 2
        let filtered = selectedIndices.filter { k in
            guard !isNewMonthDay[k] else { return true }
            return !newMonthPositions.contains(where: { abs($0 - k) < minGap })
        }
        return filtered.sorted().enumerated().map { ordinal, k in
            let pair = days[k]
            let label = isNewMonthDay[k] ? monDF.string(from: pair.date) : dayDF.string(from: pair.date)
            return AxisTick(id: ordinal, normX: Double(pair.index) / Double(total), label: label)
        }
    }

    private static func threeMonthTicks(data: [StockHistoryPoint]) -> [AxisTick] {
        guard !data.isEmpty else { return [] }
        let total = max(data.count - 1, 1); let cal = jakartaCal
        let dayDF = DateFormatter(); dayDF.timeZone = TimeZone(identifier: "Asia/Jakarta")!; dayDF.dateFormat = "d"
        let monDF = DateFormatter(); monDF.locale = Locale(identifier: "id_ID")
        monDF.timeZone = TimeZone(identifier: "Asia/Jakarta")!; monDF.dateFormat = "MMM"
        var ticks: [AxisTick] = []; var ordinal = 0
        ticks.append(AxisTick(id: ordinal, normX: 0.0, label: dayDF.string(from: data[0].date))); ordinal += 1
        let months = firstIndexPerMonth(data); let firstMonth = cal.component(.month, from: data[0].date)
        for m in months {
            guard cal.component(.month, from: m.date) != firstMonth else { continue }
            ticks.append(AxisTick(id: ordinal, normX: Double(m.index) / Double(total), label: monDF.string(from: m.date)))
            ordinal += 1
        }
        return ticks
    }

    private static func ytdTicks(data: [StockHistoryPoint]) -> [AxisTick] {
        guard !data.isEmpty else { return [] }
        let total = max(data.count - 1, 1); let cal = jakartaCal
        let monDF = DateFormatter(); monDF.locale = Locale(identifier: "id_ID")
        monDF.timeZone = TimeZone(identifier: "Asia/Jakarta")!; monDF.dateFormat = "MMM"
        var ticks: [AxisTick] = []; var ordinal = 0
        ticks.append(AxisTick(id: ordinal, normX: 0.0, label: "Jan")); ordinal += 1
        let firstMonth = cal.component(.month, from: data[0].date)
        for m in firstIndexPerMonth(data) {
            guard cal.component(.month, from: m.date) != firstMonth else { continue }
            ticks.append(AxisTick(id: ordinal, normX: Double(m.index) / Double(total), label: monDF.string(from: m.date)))
            ordinal += 1
        }
        return ticks
    }

    private static func oneYearTicks(data: [StockHistoryPoint]) -> [AxisTick] {
        guard !data.isEmpty else { return [] }
        let total = max(data.count - 1, 1); let cal = jakartaCal
        let currentYear = cal.component(.year, from: Date())
        let targets = [
            (year: currentYear - 1, month: 6, label: "Jun"),
            (year: currentYear - 1, month: 9, label: "Sep"),
            (year: currentYear,     month: 1, label: "\(currentYear)"),
            (year: currentYear,     month: 4, label: "Apr")
        ]
        var ticks: [AxisTick] = []; var ordinal = 0
        for t in targets {
            var comps = DateComponents(); comps.year = t.year; comps.month = t.month; comps.day = 1
            comps.timeZone = cal.timeZone
            guard let targetDate = cal.date(from: comps), let idx = nearestIndex(in: data, to: targetDate) else { continue }
            ticks.append(AxisTick(id: ordinal, normX: Double(idx) / Double(total), label: t.label)); ordinal += 1
        }
        return ticks
    }

    private static func fiveYearTicks(data: [StockHistoryPoint]) -> [AxisTick] {
        guard !data.isEmpty else { return [] }
        let total = max(data.count - 1, 1); let cal = jakartaCal
        let lastYear = cal.component(.year, from: data.last!.date)
        let firstYear = cal.component(.year, from: data.first!.date)
        var ticks: [AxisTick] = []; var ordinal = 0
        for year in max(firstYear, lastYear - 5)...lastYear {
            var comps = DateComponents(); comps.year = year; comps.month = 1; comps.day = 1
            comps.timeZone = cal.timeZone
            guard let targetDate = cal.date(from: comps), let idx = nearestIndex(in: data, to: targetDate) else { continue }
            ticks.append(AxisTick(id: ordinal, normX: Double(idx) / Double(total), label: "\(year)")); ordinal += 1
        }
        return ticks
    }
}

// MARK: - Animated Tick View

private struct AnimatedTickView: View {
    let tick: AxisTick; let targetX: CGFloat; let exitX: CGFloat
    let hPad: CGFloat; let innerWidth: CGFloat; let isEntering: Bool

    @State private var currentX: CGFloat? = nil
    private let spring: Animation = .spring(response: 0.55, dampingFraction: 0.80)
    private var labelOffset: CGFloat {
        if tick.normX <= 0.10 { return 8 }
        if tick.normX >= 0.90 { return -8 }
        return 0
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(tick.label)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundColor(Color.black.opacity(0.55))
                .fixedSize().lineLimit(1).offset(x: labelOffset)
        }
        .position(x: currentX ?? (isEntering ? exitX : targetX), y: 10)
        .opacity(currentX == nil ? 0 : 1)
        .onAppear {
            if isEntering {
                currentX = exitX
                DispatchQueue.main.async { withAnimation(spring) { currentX = targetX } }
            } else { currentX = targetX }
        }
        .onChange(of: targetX) { _, newX in withAnimation(spring) { currentX = newX } }
    }
}

// MARK: - Exiting Tick View

private struct ExitingTickView: View {
    let tick: AxisTick; let startX: CGFloat; let exitX: CGFloat; let spring: Animation

    @State private var gone = false
    private var labelOffset: CGFloat {
        if tick.normX <= 0.10 { return 14 }
        if tick.normX >= 0.90 { return -14 }
        return 0
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(tick.label)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundColor(Color.black.opacity(0.55))
                .fixedSize().lineLimit(1).offset(x: labelOffset)
        }
        .position(x: gone ? exitX : startX, y: 10)
        .opacity(gone ? 0 : 1)
        .onAppear { withAnimation(spring) { gone = true } }
    }
}

// MARK: - XAxisAnimatedLabels

struct XAxisAnimatedLabels<VM: ChartViewModelProtocol>: View {
    @ObservedObject var chartVM: VM
    let chartSize: CGSize

    private let hPad: CGFloat = 4
    @State private var renderedTicks: [AxisTick] = []
    @State private var exitingTicks:  [AxisTick] = []
    @State private var lastKnownX:    [Int: CGFloat] = [:]

    private var innerWidth: CGFloat { max(chartSize.width - hPad * 2, 1) }
    private var exitX:      CGFloat { chartSize.width + 40 }

    var body: some View {
        ZStack {
            ForEach(renderedTicks) { tick in
                let exponent = chartVM.selectedRange.xSpacingExponent
                let targetX  = hPad + pow(CGFloat(tick.normX), exponent) * innerWidth
                let isNew    = lastKnownX[tick.id] == nil
                AnimatedTickView(tick: tick, targetX: targetX, exitX: exitX,
                                 hPad: hPad, innerWidth: innerWidth, isEntering: isNew)
            }
            ForEach(exitingTicks) { tick in
                ExitingTickView(tick: tick, startX: lastKnownX[tick.id] ?? exitX, exitX: exitX,
                                spring: .spring(response: 0.6, dampingFraction: 0.78))
            }
        }
        .frame(height: 20).clipped()
        .onChange(of: chartVM.dataPoints) { _, newData in updateTicks(from: newData) }
        .onChange(of: chartVM.selectedRange) { _, _ in
            if !chartVM.dataPoints.isEmpty { updateTicks(from: chartVM.dataPoints) }
        }
        .onAppear {
            if !chartVM.dataPoints.isEmpty {
                renderedTicks = AxisTickGenerator.ticks(for: chartVM.dataPoints, range: chartVM.selectedRange, chartVM: chartVM)
            }
        }
    }

    private func updateTicks(from data: [StockHistoryPoint]) {
        guard chartSize.width > 0 else { return }
        let newTicks = AxisTickGenerator.ticks(for: data, range: chartVM.selectedRange, chartVM: chartVM)
        let newIDs   = Set(newTicks.map(\.id))
        let leaving  = renderedTicks.filter { !newIDs.contains($0.id) }
        if !leaving.isEmpty {
            exitingTicks = leaving
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) {
                exitingTicks = exitingTicks.filter { t in !leaving.contains(t) }
            }
        }
        let stayingIDs = Set(renderedTicks.map(\.id)).intersection(newIDs)
        for tick in newTicks where stayingIDs.contains(tick.id) {
            lastKnownX[tick.id] = hPad + CGFloat(tick.normX) * innerWidth
        }
        renderedTicks = newTicks
    }
}
