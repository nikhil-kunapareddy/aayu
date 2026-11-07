import Foundation
import Testing
@testable import AayuKit

/// The Sleep Breakdown's x axis: its tick step follows the night's length and
/// the chart's width, and interior ticks keep clear of the end chips.
@Suite("Hypnogram axis")
struct HypnogramAxisTests {
    let calendar = Theme.gregorian(Sample.utc)

    private func date(_ time: String) throws -> Date {
        try Date(time + "Z", strategy: .iso8601)
    }

    private func hours(_ h: Double) -> TimeInterval { h * 3600 }

    @Test(arguments: [
        (1.5, 900.0, 15),    // a nap: quarter hours
        (3.5, 900.0, 30),    // a short night: half hours
        (8.0, 900.0, 60),    // a usual night: hours
        (8.0, 500.0, 60),
        (14.0, 700.0, 120),  // a long night in a narrow window: every two hours
        (14.0, 300.0, 180),
        (20.0, 300.0, 240),
        (24.0, 200.0, 240),  // nothing fits: the coarsest step
    ])
    func stepFollowsLengthAndWidth(span: Double, width: Double, step: Int) {
        #expect(HypnogramChart.tickStep(span: hours(span), width: width) == step)
    }

    @Test func usualNightTicksEveryHourClearOfTheEnds() throws {
        let ticks = HypnogramChart.timeTicks(from: try date("2026-05-01T22:40:00"), to: try date("2026-05-02T07:10:00"),
                                             width: 900, calendar: calendar)
        // 23:00 and 07:00 would sit under the bedtime and wake chips.
        let expected = try ["2026-05-01T22:40:00", "2026-05-02T00:00:00", "2026-05-02T01:00:00", "2026-05-02T02:00:00",
                            "2026-05-02T03:00:00", "2026-05-02T04:00:00", "2026-05-02T05:00:00", "2026-05-02T06:00:00",
                            "2026-05-02T07:10:00"].map(date)
        #expect(ticks == expected)
    }

    @Test func shortNightTicksEveryHalfHour() throws {
        let ticks = HypnogramChart.timeTicks(from: try date("2026-05-02T03:10:00"), to: try date("2026-05-02T06:40:00"),
                                             width: 900, calendar: calendar)
        let expected = try ["2026-05-02T03:10:00", "2026-05-02T04:00:00", "2026-05-02T04:30:00", "2026-05-02T05:00:00",
                            "2026-05-02T05:30:00", "2026-05-02T06:00:00", "2026-05-02T06:40:00"].map(date)
        #expect(ticks == expected)
    }

    @Test func longNightTicksOnEvenHours() throws {
        let ticks = HypnogramChart.timeTicks(from: try date("2026-05-01T20:00:00"), to: try date("2026-05-02T10:00:00"),
                                             width: 700, calendar: calendar)
        let interior = ticks.dropFirst().dropLast()
        #expect(!interior.isEmpty)
        #expect(interior.allSatisfy { calendar.component(.minute, from: $0) == 0
                                      && calendar.component(.hour, from: $0) % 2 == 0 })
    }

    @Test func unmeasuredWidthStillGivesTicks() throws {
        let start = try date("2026-05-01T23:00:00"), end = try date("2026-05-02T07:00:00")
        #expect(HypnogramChart.timeTicks(from: start, to: end, width: 0, calendar: calendar)
                == HypnogramChart.timeTicks(from: start, to: end, width: 600, calendar: calendar))
        #expect(HypnogramChart.timeTicks(from: start, to: start, width: 900, calendar: calendar) == [start, start])
    }
}
