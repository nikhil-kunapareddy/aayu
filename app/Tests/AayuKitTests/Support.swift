import Foundation
import Testing
@testable import AayuKit

/// Synthetic payloads (no real data), decoded the way the app decodes them.
enum Sample {
    static let utc = TimeZone(identifier: "UTC")!
    static let decoder = PayloadDecoder.make(timeZone: utc)

    /// The fixture as raw JSON.
    static func fixture() throws -> Data {
        let url = try #require(Bundle.module.url(forResource: "dashboard", withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    /// The fixture as a dictionary, for tests that patch it.
    static func object() throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: fixture()) as? [String: Any])
    }

    static func decode(_ object: [String: Any]) throws -> Dashboard {
        try decoder.decode(Dashboard.self, from: JSONSerialization.data(withJSONObject: object))
    }

    /// The fixture with a different selection, night and optional weight.
    static func dashboard(selection: String = "2026-05", night: String? = "2026-05-31",
                          weight: Bool = true) throws -> Dashboard {
        var o = try object()
        o["selection"] = selection
        if !weight { o["weight"] = NSNull() }
        if let night, var h = o["hypnogram"] as? [String: Any] {
            h["night"] = night
            o["hypnogram"] = h
        } else if night == nil {
            o["hypnogram"] = NSNull()
        }
        return try decode(o)
    }

    /// A scratch defaults suite with a folder chosen.
    static func defaults(folder: String = "/tmp/zepp") throws -> UserDefaults {
        let suite = "AayuKitTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defaults.register(defaults: Pref.defaults)
        defaults.set(folder, forKey: Pref.folder)
        return defaults
    }
}

/// A stand-in for the helper. It records each request and answers `dashboard`
/// from `reply`, or — while `holding` — keeps the reply until the test releases it.
actor FakeBackend: BackendClient {
    struct WrongType: Error {}

    nonisolated let events: AsyncStream<String>
    private let eventSink: AsyncStream<String>.Continuation
    private let reply: @Sendable (DashboardRequest) throws -> Dashboard
    private(set) var methods: [String] = []
    private(set) var dashboardRequests: [DashboardRequest] = []
    private var holding = false
    private var held: [CheckedContinuation<Dashboard, any Error>] = []
    private var waiters: [(count: Int, cont: CheckedContinuation<Void, Never>)] = []

    init(reply: @escaping @Sendable (DashboardRequest) throws -> Dashboard = { r in
        try Sample.dashboard(selection: r.selection ?? "2026-05", night: r.night ?? "2026-05-31")
    }) {
        self.reply = reply
        (events, eventSink) = AsyncStream.makeStream(of: String.self)
    }

    func call<Request: BackendRequest>(_ request: Request) async throws -> Request.Result {
        methods.append(Request.method)
        let result: Any
        switch request {
        case let r as DashboardRequest:
            dashboardRequests.append(r)
            notify()
            result = holding ? try await withCheckedThrowingContinuation { held.append($0); notify() } : try reply(r)
        case is WatchRequest:
            result = Ignored()
        default:
            result = FolderStatus(exists: true, found: ["Sleep"], total: 6, error: nil)
        }
        guard let typed = result as? Request.Result else { throw WrongType() }
        return typed
    }

    func hold() { holding = true }

    func push(_ event: String) { eventSink.yield(event) }

    /// Answer the `index`th held dashboard request (in arrival order).
    func release(_ index: Int, with result: Result<Dashboard, any Error>) {
        held[index].resume(with: result)
    }

    /// Wait until `count` dashboard requests have arrived (held ones included).
    func waitForDashboardRequests(_ count: Int) async {
        if seen >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }

    private var seen: Int { holding ? held.count : dashboardRequests.count }

    private func notify() {
        let ready = waiters.filter { $0.count <= seen }
        waiters.removeAll { $0.count <= seen }
        ready.forEach { $0.cont.resume() }
    }
}
