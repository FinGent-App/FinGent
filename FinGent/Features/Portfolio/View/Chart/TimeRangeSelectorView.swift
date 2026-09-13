// Features/Portfolio/View/Chart/TimeRangeSelectorView.swift

import SwiftUI

struct TimeRangeSelectorView<VM: ChartViewModelProtocol>: View {
    @ObservedObject var chartVM: VM
    let onRangeChange: () -> Void
    var tintColor: Color = Color.teal

    var body: some View {
        Picker("Range", selection: $chartVM.selectedRange) {
            ForEach(TimeRange.allCases, id: \.self) { range in
                Text(range.rawValue).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .tint(tintColor)
        .onChange(of: chartVM.selectedRange) { _, _ in
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onRangeChange()
            Task { await chartVM.fetchChartData() }
        }
    }
}
