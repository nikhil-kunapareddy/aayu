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
        let request = DashboardRequest(selection: nil, units: .lbs, defaultRange: .month, night: nil)
        #expect(try line(request, id: 7) == """
            {"id":7,"method":"dashboard","params":{"default_range":"month","night":null,"selection":null,"units":"lbs"}}\n
            """)
    }

    @Test func dashboardWithValues() throws {
        let request = DashboardRequest(selection: "2026-05", units: .kg, defaultRange: .last30, night: "2026-05-30")
        #expect(try line(request) == """
            {"id":1,"method":"dashboard","params":{"default_range":"last30","night":"2026-05-30","selection":"2026-05","units":"kg"}}\n
            """)
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
