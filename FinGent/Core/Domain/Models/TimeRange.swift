// Core/Domain/Models/TimeRange.swift

import SwiftUI

enum TimeRange: String, CaseIterable, Identifiable, Sendable {
    case oneDay     = "1D"
    case oneWeek    = "1W"
    case oneMonth   = "1M"
    case threeMonth = "3M"
    case ytd        = "YTD"
    case oneYear    = "1Y"
    case fiveYear   = "5Y"
    case all        = "All"

    var id: String { rawValue }

    var isIntraday: Bool { self == .oneDay || self == .oneWeek }

    var xSpacingExponent: CGFloat {
        switch self {
        case .oneDay:     return 1.0
        case .oneWeek:    return 1.0
        case .oneMonth:   return 0.88
        case .threeMonth: return 0.78
        case .ytd:        return 0.72
        case .oneYear:    return 0.65
        case .fiveYear:   return 0.55
        case .all:        return 0.50
        }
    }

    var apiPeriod: String {
        switch self {
        case .oneDay:     return "24h"
        case .oneWeek:    return "1w"
        case .oneMonth:   return "1m"
        case .threeMonth: return "3m"
        case .ytd:        return "ytd"
        case .oneYear:    return "1y"
        case .fiveYear:   return "5y"
        case .all:        return "5y"
        }
    }
}
