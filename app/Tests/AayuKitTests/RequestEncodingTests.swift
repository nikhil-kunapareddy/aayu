import Foundation
import Testing
@testable import AayuKit

/// Request lines must match backend/aayu_backend/server.py: method names from
/// `Server.METHODS`, params named as the Python arguments, nil sent as null.
@Suite("Request encoding")
struct RequestEncodingTests {
    private func line(_ request: some BackendRequest, id: Int = 1) throws -> String {
        try #require(String(data: Backend.line(for: request, id: id), encoding: .utf8))
    }

    @Test func dashboardSendsNullsForMissingSelectionAndNight() throws {
        let request = DashboardRequest(selection: nil, units: .lbs, defaultRange: .month, night: nil,
                                       bedtime: .bedtime, wakeTime: .wakeTime)
        #expect(try line(request, id: 7) == """
            {"id":7,"method":"dashboard","params":{"bedtime":"23:30","default_range":"month","night":null,\
            "selection":null,"units":"lbs","wake_time":"06:30"}}\n
            """)
    }

    @Test func dashboardWithValues() throws {
        let request = DashboardRequest(selection: "2026-05", units: .kg, defaultRange: .last30, night: "2026-05-30",
                                       bedtime: ClockTime(hour: 0, minute: 5), wakeTime: ClockTime(hour: 9, minute: 0))
        #expect(try line(request) == """
            {"id":1,"method":"dashboard","params":{"bedtime":"00:05","default_range":"last30","night":"2026-05-30",\
            "selection":"2026-05","units":"kg","wake_time":"09:00"}}\n
            """)
    }

    /// "HH:MM", 24-hour, as server.py's `_clock_time` accepts.
    @Test func clockTimeRawValues() {
        #expect(ClockTime.bedtime.rawValue == "23:30" && ClockTime.wakeTime.rawValue == "06:30")
        #expect(ClockTime(rawValue: "07:05") == ClockTime(hour: 7, minute: 5))
        #expect(ClockTime(rawValue: "00:00") == ClockTime(hour: 0, minute: 0))
        for bad in ["24:00", "12:60", "7:30", "07:3", "+1:30", "07:30:00", "0730", "", "ab:cd"] {
            #expect(ClockTime(rawValue: bad) == nil, "\(bad)")
        }
    }

    @Test func clockTimeDates() throws {
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        for time in [ClockTime.bedtime, .wakeTime, ClockTime(hour: 0, minute: 0), ClockTime(hour: 2, minute: 30)] {
            #expect(ClockTime(time.date(timeZone: tokyo), timeZone: tokyo) == time)
            #expect(ClockTime(time.date()) == time)
        }
    }

    @Test func otherMethods() throws {
        #expect(try line(OpenRequest(folder: "/Users/me/Zepp")) == """
            {"id":1,"method":"open","params":{"folder":"/Users/me/Zepp"}}\n
            """)
        #expect(try line(ReloadRequest(), id: 2) == #"{"id":2,"method":"reload","params":{}}"# + "\n")
        #expect(try line(StatusRequest(folder: "/x"), id: 3) == #"{"id":3,"method":"status","params":{"folder":"/x"}}"# + "\n")
        #expect(try line(WatchRequest(enabled: true), id: 4) == #"{"id":4,"method":"watch","params":{"enabled":true}}"# + "\n")
    }

    @Test func methodNamesMatchTheServer() {
        let methods = [OpenRequest.method, ReloadRequest.method, StatusRequest.method,
                       DashboardRequest.method, WatchRequest.method]
        #expect(methods == ["open", "reload", "status", "dashboard", "watch"])
    }
}
