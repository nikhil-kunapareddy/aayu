import Foundation

// Text for numbers, dates and ranges. Helpers default to the user's locale,
// calendar and timezone; tests pass fixed ones. The backend's 'YYYY-MM' and
// 'YYYY-MM-DD' strings are Gregorian, so they're parsed with `gregorian(_:)`.
extension Theme {
    // ── Ranges and days ──────────────────────────────────────────────────────
    /// Picker label for 'YYYY-MM' ("May 2026") or 'last30'.
    static func rangeLabel(_ value: String, locale: Locale = .autoupdatingCurrent,
                           calendar: Calendar = .autoupdatingCurrent,
                           timeZone: TimeZone = .autoupdatingCurrent) -> String {
        if value == "last30" { return "Last 30 days" }
        guard let date = month(value, timeZone: timeZone) else { return value }
        return date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone)
            .month(.wide).year())
    }

    /// "for May 2026" / "for the last 30 days" — the header subtitle's tail.
    static func rangePhrase(_ value: String, locale: Locale = .autoupdatingCurrent,
                            calendar: Calendar = .autoupdatingCurrent,
                            timeZone: TimeZone = .autoupdatingCurrent) -> String {
        value == "last30" ? "the last 30 days" : rangeLabel(value, locale: locale, calendar: calendar, timeZone: timeZone)
    }

    /// 'YYYY-MM-DD' (a sleep night) → its midnight.
    static func day(_ value: String, timeZone: TimeZone = .autoupdatingCurrent) -> Date? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return gregorian(timeZone).date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// 'YYYY-MM' → midnight on the month's first day.
    static func month(_ value: String, timeZone: TimeZone = .autoupdatingCurrent) -> Date? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return gregorian(timeZone).date(from: DateComponents(year: parts[0], month: parts[1]))
    }

    /// A Gregorian calendar in `timeZone`, whatever calendar the user picked.
    static func gregorian(_ timeZone: TimeZone = .autoupdatingCurrent) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    // ── Numbers ──────────────────────────────────────────────────────────────
    /// 125 → "2h 5m".
    static func duration(minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    /// 0.234 → "23.4%".
    static func percent(_ share: Double, locale: Locale = .autoupdatingCurrent) -> String {
        share.formatted(.percent.precision(.fractionLength(1)).locale(locale))
    }

    /// `value` rounded to `decimals` places, half to even (as number formatting rounds).
    static func rounded(_ value: Double, decimals: Int) -> Double {
        let scale = pow(10, Double(decimals))
        return (value * scale).rounded(.toNearestOrEven) / scale
    }

    /// "+0.6", "−3", "±0" — signed, with a real minus sign. The sign is the
    /// rounded value's, so −0.04 at one decimal is "±0.0", not "−0.0".
    static func signed(_ value: Double, decimals: Int = 0, locale: Locale = .autoupdatingCurrent) -> String {
        let shown = rounded(value, decimals: decimals)
        let magnitude = abs(shown).formatted(.number.precision(.fractionLength(decimals)).locale(locale))
        return (shown > 0 ? "+" : shown < 0 ? "−" : "±") + magnitude
    }

    // ── Chart axes ───────────────────────────────────────────────────────────
    static func dayAfter(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(86400)
    }

    /// X-axis ticks for start…end: the first and last day, plus one every
    /// `everyDays` between (dropping any that crowd the last). Ticks sit at noon
    /// so they line up under day-wide bars.
    static func dayTicks(from start: Date, to end: Date, everyDays: Int, calendar: Calendar = .current) -> [Date] {
        var days = [start]
        var next = calendar.date(byAdding: .day, value: everyDays, to: start)
        while let t = next, (calendar.dateComponents([.day], from: t, to: end).day ?? 0) >= 7 {
            days.append(t)
            next = calendar.date(byAdding: .day, value: everyDays, to: t)
        }
        days.append(end)
        return days.map { $0.addingTimeInterval(12 * 3600) }
    }

    /// Weeks run Monday–Sunday, as in the backend's week bucketing.
    static let mondayCalendar: Calendar = {
        var cal = Calendar.current
        cal.firstWeekday = 2
        return cal
    }()
}
