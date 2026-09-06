// Common/Formatters/NumberFormatters.swift

import Foundation

/// Centralized number formatting utilities.
/// All formatting in one place — no duplicated formatter setup across views/VMs.
enum NumberFormatters {

    // MARK: - Currency

    static func rupiah(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "Rp "
        formatter.currencyGroupingSeparator = "."
        formatter.currencyDecimalSeparator = ","
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "Rp 0"
    }

    /// e.g. "10.500" (no currency prefix)
    static func stockPrice(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }

    /// e.g. "1.5jt", "250rb", "2.1M"
    static func compact(_ value: Double) -> String {
        if value >= 1_000_000_000 {
            return String(format: "%.1fM", value / 1_000_000_000)
        } else if value >= 1_000_000 {
            return String(format: "%.1fjt", value / 1_000_000)
        } else {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.groupingSeparator = "."
            formatter.maximumFractionDigits = 0
            return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
        }
    }

    /// For text input fields — shows "1.000.000" style
    static func inputFormatted(_ value: Double) -> String {
        guard value > 0 else { return "" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }

    /// Strip formatting separators to get raw Double from a formatted string
    static func parseInput(_ text: String) -> Double {
        let cleaned = text
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")
            .filter { $0.isNumber }
        return Double(cleaned) ?? 0
    }

    // MARK: - Volume

    static func volume(_ value: Int) -> String {
        let d = Double(value)
        if d >= 1_000_000_000 { return String(format: "%.2fB", d / 1_000_000_000) }
        if d >= 1_000_000 { return String(format: "%.2fM", d / 1_000_000) }
        if d >= 1_000 { return String(format: "%.1fK", d / 1_000) }
        return "\(value)"
    }

    // MARK: - English locale (for Siri TTS)

    static func englishDecimal(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US")
        formatter.groupingSeparator = ","
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }

    // MARK: - Spoken Indonesian (for Siri)

    static func spokenRupiah(_ value: Double) -> String {
        if value >= 1_000_000_000_000 {
            return "\(spokenDecimal(value / 1_000_000_000_000)) triliun rupiah"
        } else if value >= 1_000_000_000 {
            return "\(spokenDecimal(value / 1_000_000_000)) miliar rupiah"
        } else if value >= 1_000_000 {
            return "\(spokenDecimal(value / 1_000_000)) juta rupiah"
        } else if value >= 1_000 {
            return "\(spokenDecimal(value / 1_000)) ribu rupiah"
        }
        return "\(Int(value)) rupiah"
    }

    private static func spokenDecimal(_ number: Double) -> String {
        number.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(number))"
            : String(format: "%.1f", number).replacingOccurrences(of: ".0", with: "")
    }
}
