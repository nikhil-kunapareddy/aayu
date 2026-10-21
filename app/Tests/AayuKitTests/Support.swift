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

    /// A folder that loaded.
    static let loaded = FolderStatus(exists: true, found: ["Sleep"], total: 6, error: nil, errorCode: nil)

    /// A folder whose load failed with `code`.
    static func failed(_ code: AppError.Code, _ message: String = "It didn't load.") -> FolderStatus {
        FolderStatus(exists: true, found: [], total: 6, error: message, errorCode: code.rawValue)
    }
}

/// Wait (up to `limit`) until `condition` holds; records an issue if it never does.
@MainActor func eventually(_ what: Comment, within limit: Duration = .seconds(5),
                           _ condition: @MainActor () -> Bool) async throws {
    let deadline = ContinuousClock.now + limit
    while !condition() {
        guard ContinuousClock.now < deadline else {
            Issue.record("Timed out waiting: \(what)")
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}

/// A stand-in for the helper. It records each request, answers `dashboard`
/// from `reply` — or, while `holding`, keeps the reply until the test
/// releases it — and `open`/`reload` with `folderStatus`.
actor FakeBackend: BackendClient {
    struct WrongType: Error {}

    nonisolated let events: AsyncStream<String>
    private let eventSink: AsyncStream<String>.Continuation
    private var reply: @Sendable (DashboardRequest) throws -> Dashboard
    private(set) var methods: [String] = []
    private(set) var dashboardRequests: [DashboardRequest] = []
    private var holding = false
    private var held: [CheckedContinuation<Dashboard, any Error>] = []
    private var waiters: [(count: Int, cont: CheckedContinuation<Void, Never>)] = []
    private var methodWaiters: [(method: String, count: Int, cont: CheckedContinuation<Void, Never>)] = []
    private var folderStatus = Sample.loaded
    private var openDelay: Duration?

    init(reply: @escaping @Sendable (DashboardRequest) throws -> Dashboard = { r in
        try Sample.dashboard(selection: r.selection ?? "2026-05", night: r.night ?? "2026-05-31")
    }) {
        self.reply = reply
        (events, eventSink) = AsyncStream.makeStream(of: String.self)
    }

    func call<Request: BackendRequest>(_ request: Request) async throws -> Request.Result {
        methods.append(Request.method)
        notifyMethods()
        let result: Any
        switch request {
        case let r as DashboardRequest:
            dashboardRequests.append(r)
            notify()
            result = holding ? try await withCheckedThrowingContinuation { held.append($0); notify() } : try reply(r)
        case is WatchRequest:
            result = Ignored()
        case is OpenRequest:
            if let openDelay { try await Task.sleep(for: openDelay) }   // throws when cancelled
            result = folderStatus
        case is ReloadRequest:
            result = folderStatus
        default:
            result = Sample.loaded
        }
        guard let typed = result as? Request.Result else { throw WrongType() }
        return typed
    }

    func hold() { holding = true }

    func push(_ event: String) { eventSink.yield(event) }

    /// From now on, answer `dashboard` with `reply`.
    func setReply(_ reply: @escaping @Sendable (DashboardRequest) throws -> Dashboard) { self.reply = reply }

    /// From now on, answer `open` and `reload` with `status`.
    func setFolderStatus(_ status: FolderStatus) { folderStatus = status }

    /// While set, `open` takes this long to answer (and throws if cancelled meanwhile).
    func setOpenDelay(_ delay: Duration?) { openDelay = delay }

    /// Answer the `index`th held dashboard request (in arrival order).
    func release(_ index: Int, with result: Result<Dashboard, any Error>) {
        held[index].resume(with: result)
    }

    /// Wait until `count` dashboard requests have arrived (held ones included).
    func waitForDashboardRequests(_ count: Int) async {
        if seen >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }

    /// Wait until `count` requests for `method` have arrived.
    func waitFor(_ method: String, count: Int = 1) async {
        if calls(method) >= count { return }
        await withCheckedContinuation { methodWaiters.append((method, count, $0)) }
    }

    func calls(_ method: String) -> Int { methods.count { $0 == method } }

    private var seen: Int { holding ? held.count : dashboardRequests.count }

    private func notify() {
        let ready = waiters.filter { $0.count <= seen }
        waiters.removeAll { $0.count <= seen }
        ready.forEach { $0.cont.resume() }
    }

    private func notifyMethods() {
        let ready = methodWaiters.filter { $0.count <= calls($0.method) }
        methodWaiters.removeAll { $0.count <= calls($0.method) }
        ready.forEach { $0.cont.resume() }
    }
}

/// A stand-in helper *process* for testing `Backend` itself: a `/bin/sh`
/// script that reads request lines on stdin and answers on stdout.
struct ScriptHelper {
    /// The script, and a log it can write to (`$LOG`).
    let url: URL
    let log: URL

    /// Sets `$id` to the id of the request in `$line` (ids come first: keys are sorted).
    static let readID = #"id=$(printf '%s\n' "$line" | sed -E 's/^\{"id":([0-9]+),.*/\1/')"#

    /// A generic answer: a loaded folder's status (open, reload, status).
    static let answerStatus = #"printf '{"id":%s,"result":{"exists":true,"found":["Sleep"],"total":6,"error":null}}\n' "$id""#

    /// Answers `watch` with null and everything else with `answerStatus`,
    /// after logging "pid line"; `extra` runs first (e.g. a `case` that exits).
    static func answering(extra: String = "") throws -> ScriptHelper {
        try ScriptHelper("""
            while IFS= read -r line; do
              printf '%s %s\\n' "$$" "$line" >> "$LOG"
              \(readID)
              \(extra)
              case "$line" in
                *'"method":"watch"'*) printf '{"id":%s,"result":null}\\n' "$id" ;;
                *) \(answerStatus) ;;
              esac
            done
            """)
    }

    init(_ body: String) throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("AayuKitTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("helper")
        log = dir.appendingPathComponent("requests.log")
        try "#!/bin/sh\nLOG='\(log.path)'\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    /// Wait (up to `limit`) until the helpers have logged `count` requests.
    func waitForRequests(_ count: Int, within limit: Duration = .seconds(10)) async throws {
        let deadline = ContinuousClock.now + limit
        while try received().count < count {
            guard ContinuousClock.now < deadline else {
                Issue.record("The helper never received \(count) request(s)")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    /// What the helpers received, as (pid, "method param") in order, e.g. ("123", "open /z").
    func received() throws -> [(pid: String, request: String)] {
        guard FileManager.default.fileExists(atPath: log.path) else { return [] }
        return try String(contentsOf: log, encoding: .utf8).split(separator: "\n").map { entry in
            let parts = entry.split(separator: " ", maxSplits: 1)
            let json = try #require(try JSONSerialization.jsonObject(with: Data(parts[1].utf8)) as? [String: Any])
            let method = try #require(json["method"] as? String)
            let params = json["params"] as? [String: Any] ?? [:]
            let param = (params["folder"] as? String) ?? (params["enabled"] as? Bool).map { "\($0)" }
            return (String(parts[0]), param.map { "\(method) \($0)" } ?? method)
        }
    }
}
