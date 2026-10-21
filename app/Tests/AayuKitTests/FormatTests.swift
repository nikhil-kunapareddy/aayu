import Foundation
import Testing
@testable import AayuKit

@Suite("Formatting")
struct FormatTests {
    let en = Locale(identifier: "en_US")
    let utc = Sample.utc
    var calendar: Calendar { Theme.gregorian(utc) }

    private func date(_ iso: String) throws -> Date {
        try Date(iso, strategy: .iso8601)
    }

    @Test(arguments: [(0, "0m"), (59, "59m"), (60, "1h 0m"), (125, "2h 5m"), (480, "8h 0m")])
    func duration(minutes: Int, text: String) {
        #expect(Theme.duration(minutes: minutes) == text)
    }

    @Test func percent() {
        #expect(Theme.percent(0, locale: en) == "0.0%")
        #expect(Theme.percent(0.123, locale: en) == "12.3%")
        #expect(Theme.percent(0.25, locale: en) == "25.0%")
        #expect(Theme.percent(1, locale: en) == "100.0%")
    }

    @Test func rangeLabelAndPhrase() {
        #expect(Theme.rangeLabel("last30") == "Last 30 days")
        #expect(Theme.rangeLabel("2026-05", locale: en, calendar: calendar, timeZone: utc) == "May 2026")
        #expect(Theme.rangeLabel("2025-12", locale: en, calendar: calendar, timeZone: utc) == "December 2025")
        #expect(Theme.rangeLabel("garbage") == "garbage")
        #expect(Theme.rangePhrase("last30") == "the last 30 days")
        #expect(Theme.rangePhrase("2026-05", locale: en, calendar: calendar, timeZone: utc) == "May 2026")
    }

    @Test func daysAndMonthsAreGregorian() throws {
        #expect(Theme.day("2026-05-31", timeZone: utc) == (try date("2026-05-31T00:00:00Z")))
        #expect(Theme.month("2026-05", timeZone: utc) == (try date("2026-05-01T00:00:00Z")))
        #expect(Theme.day("2026-05") == nil)
        #expect(Theme.month("2026-05-31") == nil)
        #expect(Theme.gregorian(utc).identifier == .gregorian)
    }

    @Test func dayAfter() throws {
        #expect(Theme.dayAfter(try date("2026-05-31T00:00:00Z"), calendar: calendar) == (try date("2026-06-01T00:00:00Z")))
    }

    @Test func dayTicksWeekly() throws {
        let ticks = Theme.dayTicks(from: try date("2026-05-01T00:00:00Z"), to: try date("2026-05-31T00:00:00Z"),
                                   everyDays: 7, calendar: calendar)
        let expected = try ["01", "08", "15", "22", "31"].map { try date("2026-05-\($0)T12:00:00Z") }
        #expect(ticks == expected)   // the 29th would crowd the 31st
    }

    @Test func dayTicksFortnightly() throws {
        let ticks = Theme.dayTicks(from: try date("2026-04-01T00:00:00Z"), to: try date("2026-05-31T00:00:00Z"),
                                   everyDays: 14, calendar: calendar)
        let expected = try ["04-01", "04-15", "04-29", "05-13", "05-31"].map { try date("2026-\($0)T12:00:00Z") }
        #expect(ticks == expected)
    }

    @Test(arguments: [
        (0.6, 1, "+0.6"), (-3, 0, "−3"), (0, 0, "±0"), (12.4, 0, "+12"), (-2.75, 1, "−2.8"),
        (-0.04, 1, "±0.0"), (0.04, 1, "±0.0"), (0.3, 0, "±0"), (-0.5, 0, "±0"), (1234.5, 1, "+1,234.5"),
    ])
    func signed(value: Double, decimals: Int, text: String) {
        #expect(Theme.signed(value, decimals: decimals, locale: en) == text)
    }

    @MainActor @Test func changeLabelToneFollowsTheRoundedValue() {
        #expect(ChangeLabel(-0.04, decimals: 1, suffix: " kg", higherIsBetter: false).tone == .neutral)
        #expect(ChangeLabel(0.3, suffix: "% vs April", higherIsBetter: true).tone == .neutral)
        #expect(ChangeLabel(0.3, suffix: "% vs April", higherIsBetter: true).change == 0)
        #expect(ChangeLabel(12.4, suffix: "%", higherIsBetter: true).tone == .better)
        #expect(ChangeLabel(-2, suffix: " bpm", higherIsBetter: false).tone == .better)
        #expect(ChangeLabel(2, suffix: " bpm", higherIsBetter: false).tone == .worse)
        #expect(ChangeLabel(-1.5, decimals: 1, suffix: " lbs", higherIsBetter: nil).tone == .neutral)
        #expect(ChangeLabel(-3, suffix: " bpm vs April", higherIsBetter: false).text == "−3 bpm vs April")
    }

    @Test func scoreText() {
        #expect(ScoreText.message(nil, nil) == "Not enough nights in this period for a score.")
        let close = ScoreParts(timing: 0.95, consistency: 0.9, stages: 1, duration: 0.92)
        #expect(ScoreText.message(88, close) == "Great sleep! Timing, schedule, stages and duration are all close to target.")
        let short = ScoreParts(timing: 0.8, consistency: 0.7, stages: 0.9, duration: 0.4)
        #expect(ScoreText.message(55, short) == "Fair sleep. More time asleep would help most (target 7.5 hours).")
        let tie = ScoreParts(timing: 0.5, consistency: 0.5, stages: 0.9, duration: 0.9)
        #expect(ScoreText.message(40, tie)
                == "A rough stretch. Bed and wake times are furthest from target (11:30 PM and 6:30 AM).")
    }

    @MainActor @Test func chartCaptions() throws {
        let d = try Sample.dashboard()
        #expect(WorkoutsChart.caption(d.workouts) == "6 sessions")
        #expect(CaloriesChart.caption(d.calories) == "avg 390 kcal")
        #expect(CaloriesChart.caption([]) == nil)
    }
}
