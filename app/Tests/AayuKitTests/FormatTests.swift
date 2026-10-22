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

    /// A Monday-first calendar in UTC, like the app's `mondayCalendar` but fixed.
    var mondayFirst: Calendar {
        var cal = calendar
        cal.firstWeekday = 2
        return cal
    }

    @Test func mondaysAtNoon() throws {
        let ticks = Theme.mondays(from: try date("2026-05-01T00:00:00Z"), to: try date("2026-05-31T00:00:00Z"),
                                  calendar: mondayFirst)
        let expected = try ["04", "11", "18", "25"].map { try date("2026-05-\($0)T12:00:00Z") }
        #expect(ticks == expected)
        // A Monday at either end counts.
        let june = Theme.mondays(from: try date("2026-06-01T00:00:00Z"), to: try date("2026-06-08T00:00:00Z"),
                                 calendar: mondayFirst)
        #expect(june == (try ["01", "08"].map { try date("2026-06-\($0)T12:00:00Z") }))
    }

    @Test func weekStartsCoverTheAxis() throws {
        let weeks = Theme.weekStarts(from: try date("2026-04-01T00:00:00Z"), through: try date("2026-05-31T00:00:00Z"),
                                     calendar: calendar)   // firstWeekday is forced to Monday
        #expect(weeks.count == 9)
        #expect(weeks.first == (try date("2026-03-30T00:00:00Z")))
        #expect(weeks.last == (try date("2026-05-25T00:00:00Z")))
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

    @Test func clockTime() {
        // The formatter puts a narrow no-break space before AM/PM.
        func text(_ time: ClockTime, _ locale: Locale) -> String {
            Theme.clockTime(time, locale: locale).replacingOccurrences(of: "\u{202F}", with: " ")
        }
        #expect(text(.bedtime, en) == "11:30 PM")
        #expect(text(.wakeTime, en) == "6:30 AM")
        #expect(text(ClockTime(hour: 0, minute: 5), en) == "12:05 AM")
        #expect(text(.bedtime, Locale(identifier: "en_GB")) == "23:30")
    }

    @Test func scoreText() {
        func message(_ score: Int?, _ parts: ScoreParts?, bedtime: ClockTime = .bedtime,
                     wakeTime: ClockTime = .wakeTime) -> String {
            ScoreText.message(score, parts, bedtime: bedtime, wakeTime: wakeTime, locale: en)
                .replacingOccurrences(of: "\u{202F}", with: " ")
        }
        #expect(message(nil, nil) == "Not enough nights in this period for a score.")
        let close = ScoreParts(timing: 0.95, consistency: 0.9, stages: 1, duration: 0.92, awakenings: 0.9)
        #expect(message(88, close)
                == "Great sleep! Timing, schedule, stages, duration and awakenings are all close to target.")
        let noStages = ScoreParts(timing: 0.95, consistency: 0.9, stages: 1, duration: 0.92, awakenings: nil)
        #expect(message(88, noStages) == "Great sleep! Timing, schedule, stages and duration are all close to target.")
        let short = ScoreParts(timing: 0.8, consistency: 0.7, stages: 0.9, duration: 0.4, awakenings: 1)
        #expect(message(55, short) == "Fair sleep. More time asleep would help most (target 7.5 hours).")
        let broken = ScoreParts(timing: 0.9, consistency: 0.9, stages: 0.9, duration: 0.9, awakenings: 0.5)
        #expect(message(72, broken) == "Good sleep. Waking less often in the night would help most.")
        let tie = ScoreParts(timing: 0.5, consistency: 0.5, stages: 0.9, duration: 0.9, awakenings: 0.5)
        #expect(message(40, tie)
                == "A rough stretch. Bed and wake times are furthest from your targets (11:30 PM and 6:30 AM).")
        #expect(message(40, tie, bedtime: ClockTime(hour: 22, minute: 0), wakeTime: ClockTime(hour: 6, minute: 0))
                == "A rough stretch. Bed and wake times are furthest from your targets (10:00 PM and 6:00 AM).")
    }

    @MainActor @Test func chartCaptions() throws {
        let d = try Sample.dashboard()
        #expect(WorkoutsChart.caption(d.workouts, calendar: mondayFirst) == "6 sessions · last 9 weeks")
        #expect(CaloriesChart.caption(d.calories) == "avg 390 kcal")
        #expect(CaloriesChart.caption([]) == nil)

        let night = try #require(d.hypnogram)
        #expect(HypnogramChart.caption(night) == "asleep · \(Theme.duration(minutes: 480)) total · 0 awakenings")
        var o = try Sample.object()
        var h = try #require(o["hypnogram"] as? [String: Any])
        h["awakenings"] = 1
        o["hypnogram"] = h
        #expect(try HypnogramChart.caption(#require(Sample.decode(o).hypnogram)).hasSuffix(" · 1 awakening"))
        h["awakenings"] = NSNull()
        o["hypnogram"] = h
        let plain = try #require(Sample.decode(o).hypnogram)
        #expect(HypnogramChart.caption(plain) == "asleep · \(Theme.duration(minutes: 480)) total")
        #expect(HypnogramChart.spokenCaption(plain) == "\(Theme.spokenDuration(minutes: 480)) in bed")
    }
}
