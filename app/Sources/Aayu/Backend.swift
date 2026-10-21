import Foundation

/// The Python backend, run as a hidden helper process.
///
/// We exchange one JSON object per line over its stdin/stdout (see
/// backend/aayu_backend/server.py): each request carries an `id` that the reply
/// echoes; lines with an `event` are pushed by the backend (auto-reload). No
/// network port is involved. If the helper dies, the next call relaunches it
/// and replays the last `open`/`watch`, so callers never notice.
actor Backend {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// A result we don't need (methods that return null).
    struct Ignored: Decodable {
        init(from decoder: Decoder) throws {}
    }

    private let onEvent: @Sendable (String) -> Void
    private var process: Process?
    private var input: FileHandle?
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]
    private var replay: [String: [String: Any]] = [:]   // last "open" / "watch" params

    /// `onEvent` is called off the main actor for each pushed event.
    init(onEvent: @escaping @Sendable (String) -> Void) {
        self.onEvent = onEvent
    }

    /// Call `method` with `params` and decode its result.
    func call<Result: Decodable>(_ method: String, _ params: [String: Any] = [:],
                                 as type: Result.Type = Result.self) async throws -> Result {
        if process == nil {
            try launch()
            for (m, p) in replay where m != method {
                _ = try await request(m, p)
            }
        }
        if method == "open" || method == "watch" {
            replay[method] = params
        }
        let raw = try await request(method, params)
        return try Backend.decoder.decode(Result.self, from: raw)
    }

    // ── Process ──────────────────────────────────────────────────────────────
    /// The helper inside Aayu.app: the frozen backend in release builds, a
    /// script running the backend from source in `make run` builds.
    private static let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/backend/aayu-backend")

    /// The live helper, so `terminateHelper()` can reach it from outside the actor.
    private static var live: Process?

    /// Stop the helper when the app quits. It normally exits by itself once
    /// its stdin closes, but not while blocked — e.g. waiting on the macOS
    /// privacy prompt for a folder in ~/Documents.
    static func terminateHelper() {
        live?.terminate()
    }

    private func launch() throws {
        signal(SIGPIPE, SIG_IGN)   // a dead helper must surface as a write error, not kill the app
        let p = Process()
        p.executableURL = Backend.helper
        let toBackend = Pipe(), fromBackend = Pipe()
        p.standardInput = toBackend
        p.standardOutput = fromBackend
        p.standardError = FileHandle.standardError
        p.terminationHandler = { [weak self] _ in
            Task { await self?.exited() }
        }
        try p.run()
        process = p
        Backend.live = p
        input = toBackend.fileHandleForWriting

        Task { [weak self] in
            for try await line in fromBackend.fileHandleForReading.bytes.lines {
                await self?.receive(line)
            }
        }
    }

    private func exited() {
        process = nil
        Backend.live = nil
        input = nil
        let failed = pending
        pending = [:]
        for cont in failed.values {
            cont.resume(throwing: Failure(message: "The data helper stopped unexpectedly. Try again."))
        }
    }

    // ── Lines ────────────────────────────────────────────────────────────────
    private func request(_ method: String, _ params: [String: Any]) async throws -> Data {
        let id = nextID
        nextID += 1
        let line = try JSONSerialization.data(withJSONObject: ["id": id, "method": method, "params": params])
            + Data("\n".utf8)
        return try await withCheckedThrowingContinuation { cont in
            pending[id] = cont
            do {
                try input?.write(contentsOf: line)
            } catch {
                pending[id] = nil
                cont.resume(throwing: error)
            }
        }
    }

    private func receive(_ line: String) {
        guard let message = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
            return
        }
        if let event = message["event"] as? String {
            onEvent(event)
            return
        }
        guard let id = message["id"] as? Int, let cont = pending.removeValue(forKey: id) else { return }
        if let error = message["error"] as? String {
            cont.resume(throwing: Failure(message: error))
            return
        }
        let result = message["result"] ?? NSNull()
        let raw = (try? JSONSerialization.data(withJSONObject: result, options: .fragmentsAllowed)) ?? Data("null".utf8)
        cont.resume(returning: raw)
    }

    /// Keys arrive in snake_case; timestamps as naive local ISO strings, read in
    /// the Mac's timezone so a midnight stays a midnight.
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = .current
        format.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        decoder.dateDecodingStrategy = .formatted(format)
        return decoder
    }()
}
