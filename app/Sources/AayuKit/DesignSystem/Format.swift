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

    /// 0.234 → "23.4%" (or "23%" with no decimals).
    static func percent(_ share: Double, decimals: Int = 1, locale: Locale = .autoupdatingCurrent) -> String {
        share.formatted(.percent.precision(.fractionLength(decimals)).locale(locale))
    }

    /// 23 → "23%".
    static func percent(whole: Int, locale: Locale = .autoupdatingCurrent) -> String {
        percent(Double(whole) / 100, decimals: 0, locale: locale)
    }

    /// Shares as whole percentages that add up to 100 (largest remainder), so a
    /// legend of rounded numbers still sums to the whole. All zero → all zero.
    static func wholePercents(_ shares: [Double]) -> [Int] {
        let total = shares.reduce(0) { $0 + max($1, 0) }
        guard total > 0 else { return shares.map { _ in 0 } }
        let exact = shares.map { max($0, 0) / total * 100 }
        var whole = exact.map { Int($0.rounded(.down)) }
        let left = 100 - whole.reduce(0, +)
        let order = exact.indices.sorted {
            let a = exact[$0] - Double(whole[$0]), b = exact[$1] - Double(whole[$1])
            return a != b ? a > b : $0 < $1
        }
        for i in order.prefix(left) { whole[i] += 1 }
        return whole
    }

    /// 51 minutes → "51 minutes", 72 → "1 hour, 12 minutes" — for VoiceOver.
    static func spokenDuration(minutes: Int, locale: Locale = .autoupdatingCurrent) -> String {
        Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .wide).locale(locale))
    }

    /// "1 session", "6 sessions" — `^[…](inflect: true)` picks the plural.
    static func sessions(_ n: Int) -> String {
        String(AttributedString(localized: "^[\(n) session](inflect: true)").characters)
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

    /// A value axis for lo…hi with about `ticks` steps of a round size (1, 2 or
    /// 5 × 10ⁿ), its ends snapped to the steps, so the top and bottom gridlines
    /// are the domain's edges. A flat or empty range still gets one step.
    static func niceAxis(_ lo: Double, _ hi: Double, ticks: Int = 4) -> (domain: ClosedRange<Double>, step: Double) {
        let lo = lo.isFinite ? lo : 0
        let hi = hi.isFinite && hi > lo ? hi : lo + 1
        let raw = (hi - lo) / Double(max(ticks, 1))
        let magnitude = pow(10, (log10(raw)).rounded(.down))
        let step = [1.0, 2, 5, 10].map { $0 * magnitude }.first { $0 >= raw * 0.999 } ?? 10 * magnitude
        let start = (lo / step).rounded(.down) * step
        var end = (hi / step).rounded(.up) * step
        if end <= start { end = start + step }
        return (start...end, step)
    }

    /// The Mondays from `start` to `end`, inclusive, at noon (under day-wide marks).
    static func mondays(from start: Date, to end: Date, calendar: Calendar = mondayCalendar) -> [Date] {
        var days: [Date] = []
        var day = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        while day <= last {
            if calendar.component(.weekday, from: day) == 2 { days.append(day.addingTimeInterval(12 * 3600)) }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }

    /// The Monday starting each week from the one holding `start` to the one holding `end`.
    static func weekStarts(from start: Date, through end: Date, calendar: Calendar = mondayCalendar) -> [Date] {
        var cal = calendar
        cal.firstWeekday = 2
        guard var week = cal.dateInterval(of: .weekOfYear, for: start)?.start else { return [] }
        var weeks: [Date] = []
        while week <= end {
            weeks.append(week)
            guard let next = cal.date(byAdding: .weekOfYear, value: 1, to: week) else { break }
            week = next
        }
        return weeks
    }

    /// Weeks run Monday–Sunday, as in the backend's week bucketing.
    static let mondayCalendar: Calendar = {
        var cal = Calendar.current
        cal.firstWeekday = 2
        return cal
    }()
}
