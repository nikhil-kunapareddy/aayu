import Foundation
import Testing
@testable import AayuKit

@Suite("Payload decoding")
struct PayloadTests {
    private func utc(_ iso: String) throws -> Date {
        try Date(iso + "Z", strategy: .iso8601)
    }

    @Test func decodesTheFixture() throws {
        let d = try Sample.decoder.decode(Dashboard.self, from: Sample.fixture())
        #expect(d.selection == "2026-05")
        #expect(d.options == ["last30", "2026-05", "2026-04", "2026-03"])
        #expect(d.window.start == (try utc("2026-05-01T00:00:00")))
        #expect(d.window.end == (try utc("2026-05-31T00:00:00")))
        #expect(d.units == "lbs")

        #expect(d.kpis.sleepScore == 78)
        #expect(d.kpis.sleepScoreChange == -3)
        #expect(d.kpis.sleepScoreParts?.consistency == 0.6)
        #expect(d.kpis.sleepScoreParts?.awakenings == 0.8)
        #expect(d.kpis.avgSteps == 8000)
        #expect(d.kpis.avgStepsChangePct == 12.5)
        #expect(d.kpis.avgSleepH == 7.2)
        #expect(d.kpis.avgSleepHChange == 0.3)
        #expect(d.kpis.avgRestingHr == 60)
        #expect(d.kpis.avgRestingHrChange == -2)
        #expect(d.kpis.weight == 150.0)
        #expect(d.kpis.weightChange == -1.5)

        #expect(d.stages.map(\.stage) == ["Deep", "REM", "Light", "Awake"])
        let h = try #require(d.hypnogram)
        #expect(h.night == "2026-05-31")
        #expect(h.nights.count == 3)
        #expect(h.start == (try utc("2026-05-30T23:00:00")))
        #expect(h.segments.count == 5)
        #expect(h.segments[1].stage == "Deep")
        #expect(h.segments[1].end == (try utc("2026-05-31T02:30:00")))
        #expect(h.totals.map(\.minutes).reduce(0, +) == h.duration)
        #expect(h.asleep == 450)
        #expect(h.awakenings == 0)

        #expect(d.workouts.weeks.count == 4)
        #expect(d.workouts.weeks[0].week == (try utc("2026-05-18T00:00:00")))
        #expect(d.calories.map(\.marker) == [true, false, true])
        #expect(d.weight?.count == 2)
    }

    @Test func timestampsAreReadInTheGivenTimeZone() throws {
        let newYork = try #require(TimeZone(identifier: "America/New_York"))
        let d = try PayloadDecoder.make(timeZone: newYork).decode(Dashboard.self, from: Sample.fixture())
        #expect(d.window.start == (try utc("2026-05-01T04:00:00")))   // local midnight, EDT
    }

    @Test func optionalSectionsMayBeNull() throws {
        var o = try Sample.object()
        o["weight"] = NSNull()
        o["hypnogram"] = NSNull()
        var kpis = try #require(o["kpis"] as? [String: Any])
        for key in ["sleep_score", "sleep_score_change", "sleep_score_parts", "avg_steps", "weight", "weight_change"] {
            kpis[key] = NSNull()
        }
        o["kpis"] = kpis
        let d = try Sample.decode(o)
        #expect(d.weight == nil)
        #expect(d.hypnogram == nil)
        #expect(d.kpis.sleepScore == nil)
        #expect(d.kpis.sleepScoreParts == nil)
        #expect(d.kpis.weight == nil)
        #expect(ChartPage.available(in: d) == [.sleep, .workouts, .calories])
    }

    @Test func replyEnvelopes() throws {
        let status = try Backend.result(FolderStatus.self, from: Data(#"""
            {"id":4,"result":{"exists":true,"found":["Sleep","Activity"],"total":6,"error":null}}
            """#.utf8), decoder: Sample.decoder)
        #expect(status.exists && status.found == ["Sleep", "Activity"] && status.total == 6 && status.error == nil)
        // `watch` returns null.
        _ = try Backend.result(Ignored.self, from: Data(#"{"id":5,"result":null}"#.utf8), decoder: Sample.decoder)
    }
}
