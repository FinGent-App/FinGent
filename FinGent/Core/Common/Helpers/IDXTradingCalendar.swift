// Core/Common/Helpers/IDXTradingCalendar.swift

import Foundation

/// Kalender hari bursa Bursa Efek Indonesia (BEI / IDX).
/// Mencakup akhir pekan (Sabtu–Minggu) dan tanggal merah resmi + cuti bersama.
enum IDXTradingCalendar {

    // MARK: - Jakarta Calendar (shared)

    static var jakartaCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        return cal
    }

    private static let jakartaFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone   = TimeZone(identifier: "Asia/Jakarta")!
        return f
    }()

    // MARK: - Public API

    /// `true` jika `date` adalah hari perdagangan bursa (bukan weekend, bukan libur).
    static func isTradingDay(_ date: Date) -> Bool {
        !isWeekend(date) && !isHoliday(date)
    }

    /// `true` jika `date` jatuh pada Sabtu atau Minggu (WIB).
    static func isWeekend(_ date: Date) -> Bool {
        let wd = jakartaCalendar.component(.weekday, from: date)
        return wd == 1 || wd == 7   // 1 = Minggu, 7 = Sabtu
    }

    /// `true` jika `date` adalah tanggal merah / cuti bersama bursa IDX.
    static func isHoliday(_ date: Date) -> Bool {
        let key = jakartaFormatter.string(from: date)
        return idxHolidays.contains(key)
    }

    /// Hari bursa terakhir sebelum `date` (tidak termasuk `date` itu sendiri).
    static func previousTradingDay(before date: Date) -> Date {
        var candidate = jakartaCalendar.date(byAdding: .day, value: -1, to: date)!
        while !isTradingDay(candidate) {
            candidate = jakartaCalendar.date(byAdding: .day, value: -1, to: candidate)!
        }
        return candidate
    }

    /// Hari bursa pertama setelah `date` (tidak termasuk `date` itu sendiri).
    static func nextTradingDay(after date: Date) -> Date {
        var candidate = jakartaCalendar.date(byAdding: .day, value: 1, to: date)!
        while !isTradingDay(candidate) {
            candidate = jakartaCalendar.date(byAdding: .day, value: 1, to: candidate)!
        }
        return candidate
    }

    // MARK: - Daftar Hari Libur Bursa IDX
    private static let idxHolidays: Set<String> = [
        "2024-01-01", "2024-02-08", "2024-02-09", "2024-03-11", "2024-03-12", "2024-03-29",
        "2024-04-08", "2024-04-09", "2024-04-10", "2024-04-11", "2024-04-12", "2024-04-15",
        "2024-05-01", "2024-05-09", "2024-05-23", "2024-05-24", "2024-06-01", "2024-06-17",
        "2024-06-18", "2024-07-07", "2024-08-17", "2024-09-16", "2024-12-25", "2024-12-26",
        "2025-01-01", "2025-01-27", "2025-01-28", "2025-01-29", "2025-03-28", "2025-03-31",
        "2025-04-01", "2025-04-02", "2025-04-03", "2025-04-04", "2025-04-07", "2025-04-18",
        "2025-05-01", "2025-05-12", "2025-05-27", "2025-05-28", "2025-05-29", "2025-06-01",
        "2025-06-06", "2025-06-27", "2025-08-17", "2025-08-18", "2025-09-05", "2025-12-25", "2025-12-26",
        "2026-01-01", "2026-01-16", "2026-03-18", "2026-03-20", "2026-03-23", "2026-04-01",
        "2026-04-02", "2026-04-03", "2026-04-06", "2026-05-01", "2026-05-16", "2026-05-27",
        "2026-05-28", "2026-06-01", "2026-06-16", "2026-08-17"
    ]
}

extension IDXTradingCalendar {

    static func lastActiveTradingDay(relativeTo now: Date = Date()) -> Date {
        isTradingDay(now) ? now : previousTradingDay(before: now)
    }

    private static let regularCloseMinutes = 15 * 60 + 50   // 15:50 WIB

    private static func minutesOfDay(_ date: Date) -> Int {
        let cal = jakartaCalendar
        return cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
    }

    private static func isFriday(_ date: Date) -> Bool {
        jakartaCalendar.component(.weekday, from: date) == 6
    }

    static func session1CloseMinutes(_ date: Date = Date()) -> Int {
        isFriday(date) ? 11 * 60 + 30 : 12 * 60
    }

    static func isMiddaySessionBreak(_ date: Date = Date()) -> Bool {
        guard isTradingDay(date) else { return false }
        let m = minutesOfDay(date)
        return isFriday(date) ? (m >= 11 * 60 + 30 && m < 14 * 60)
                              : (m >= 12 * 60      && m < 13 * 60 + 30)
    }

    static func isSessionOpen(_ date: Date = Date()) -> Bool {
        guard isTradingDay(date) else { return false }
        let m = minutesOfDay(date)
        return m >= 9 * 60 && m < regularCloseMinutes && !isMiddaySessionBreak(date)
    }
}
