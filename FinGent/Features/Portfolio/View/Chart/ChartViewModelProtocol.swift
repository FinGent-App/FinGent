// Features/Portfolio/View/Chart/ChartViewModelProtocol.swift

import Foundation
import SwiftUI

@MainActor
protocol ChartViewModelProtocol: ObservableObject {

    var dataPoints:    [StockHistoryPoint] { get }
    var selectedRange: TimeRange           { get set }
    var isLoading:     Bool                { get }

    var minPrice:    Double { get }
    var maxPrice:    Double { get }
    var startPrice:  Double { get }
    var latestPrice: Double { get }

    var oneDayTotalSlots:  Int { get }
    var oneDayOpenMinutes: Int { get }

    func oneDaySlotIndex(for date: Date) -> Int
    func fetchChartData() async
}
