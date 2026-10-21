import Foundation
import os
import Synchronization

/// The Python backend, run as a hidden helper process.
///
/// We exchange one JSON object per line over its stdin/stdout (see
/// backend/aayu_backend/server.py): each request carries an `id` that the reply
/// echoes; lines with an `event` are pushed by the backend (auto-reload). No
/// network port is involved. If the helper dies, the next call relaunches it
/// and replays the last `open`/`watch`, so callers never notice.
///
/// The helper's stderr is forwarded line by line to the unified log and to the
/// app's own stderr (which `make run` writes to its log file).
actor Backend: BackendClient {
    /// The helper inside Aayu.app: the frozen backend in release builds, a
    /// script running the backend from source in `make run` builds.
    static let bundledHelper = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/backend/aayu-backend")

    /// Methods whose last request is replayed to a relaunched helper, in this order.
    private static let replayed = [OpenRequest.method, WatchRequest.method]

    /// The live helper, so `terminateHelper()` can reach it from outside the actor.
    private static let live = Mutex<Process?>(nil)

    nonisolated let events: AsyncStream<String>
    private let eventSink: AsyncStream<String>.Continuation
    private let helper: URL
    private let decoder: JSONDecoder

    private var process: Process?
    private var input: FileHandle?
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<Data, any Error>] = [:]
    private var replay: [String: any BackendRequest] = [:]   // last "open" / "watch"
    private var launches = 0

    init(helper: URL = Backend.bundledHelper, decoder: JSONDecoder = PayloadDecoder.make()) {
        self.helper = helper
        self.decoder = decoder
        (events, eventSink) = AsyncStream.makeStream(of: String.self)
    }

    deinit {
        eventSink.finish()
    }

    /// Send `request` and decode its result, launching the helper first if needed.
    func call<Request: BackendRequest>(_ request: Request) async throws -> Request.Result {
        if process == nil {
            try launch()
            for method in Self.replayed where method != Request.method {
                guard let previous = replay[method] else { continue }
                Log.backend.info("Replaying \(method, privacy: .public) to the new helper")
                _ = try await send(previous)
            }
        }
        if Self.replayed.contains(Request.method) {
            replay[Request.method] = request
        }
        return try await send(request)
    }

    /// Stop the helper when the app quits. It normally exits by itself once
    /// its stdin closes, but not while blocked — e.g. waiting on the macOS
    /// privacy prompt for a folder in ~/Documents.
    static func terminateHelper() {
        guard let process = live.withLock({ $0 }) else { return }
        Log.backend.info("Stopping helper, pid \(process.processIdentifier)")
        process.terminate()
    }

    // ── Wire format ──────────────────────────────────────────────────────────
    /// One request line: `{"id":…,"method":…,"params":{…}}` and a newline.
    static func line<Request: BackendRequest>(for request: Request, id: Int) throws -> Data {
        try encoder.encode(Envelope(id: id, method: Request.method, params: request)) + Data("\n".utf8)
    }

    /// The `result` of a reply line.
    static func result<Result: Decodable>(_ type: Result.Type, from line: Data, decoder: JSONDecoder) throws -> Result {
        try decoder.decode(Reply<Result>.self, from: line).result
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    private struct Envelope<Params: Encodable>: Encodable {
        let id: Int
        let method: String
        let params: Params
    }

    private struct Reply<Result: Decodable>: Decodable {
        let result: Result
    }

    /// What `receive` reads from every line before handing it on.
    private struct Incoming: Decodable {
        let id: Int?
        let event: String?
        let error: String?
    }

    // ── Process ──────────────────────────────────────────────────────────────
    private func launch() throws {
        signal(SIGPIPE, SIG_IGN)   // a dead helper must surface as a write error, not kill the app
        let p = Process()
        p.executableURL = helper
        let toBackend = Pipe(), fromBackend = Pipe(), helperLog = Pipe()
        p.standardInput = toBackend
        p.standardOutput = fromBackend
        p.standardError = helperLog
        p.terminationHandler = { [weak self] p in
            let pid = p.processIdentifier, status = p.terminationStatus, reason = p.terminationReason
            Task { await self?.exited(pid: pid, status: status, reason: reason) }
        }
        launches += 1
        do {
            try p.run()
        } catch {
            Log.backend.error("""
                Couldn't launch the helper at \(self.helper.path, privacy: .private): \
                \(error.localizedDescription, privacy: .private)
                """)
            throw error
        }
        let verb = launches == 1 ? "Launched" : "Relaunched"
        Log.backend.notice("\(verb, privacy: .public) helper, pid \(p.processIdentifier)")
        process = p
        Self.live.withLock { $0 = p }
        input = toBackend.fileHandleForWriting

        let replies = fromBackend.fileHandleForReading
        Task { [weak self] in
            do {
                for try await line in replies.bytes.lines {
                    await self?.receive(line)
                }
            } catch {
                Log.wire.error("Stopped reading replies: \(error.localizedDescription, privacy: .private)")
            }
        }
        Self.forward(helperLog.fileHandleForReading)
    }

    /// Pass the helper's stderr on, line by line: to the unified log (category
    /// "helper") and to our own stderr.
    private static func forward(_ stderr: FileHandle) {
        Task.detached(priority: .utility) {
            do {
                for try await line in stderr.bytes.lines {
                    Log.helper.notice("\(line, privacy: .private)")
                    try? FileHandle.standardError.write(contentsOf: Data((line + "\n").utf8))
                }
            } catch {
                Log.backend.error("Stopped reading the helper's stderr: \(error.localizedDescription, privacy: .private)")
            }
        }
    }

    private func exited(pid: Int32, status: Int32, reason: Process.TerminationReason) {
        let failed = pending
        process = nil
        input = nil
        pending = [:]
        Self.live.withLock { live in
            if live?.processIdentifier == pid { live = nil }
        }
        let how = reason == .uncaughtSignal ? "signal" : "status"
        if reason == .exit, status == 0, failed.isEmpty {
            Log.backend.notice("Helper exited, pid \(pid), \(how, privacy: .public) \(status)")
        } else {
            Log.backend.error("""
                Helper exited, pid \(pid), \(how, privacy: .public) \(status), \
                with \(failed.count) request(s) waiting
                """)
        }
        for cont in failed.values {
            cont.resume(throwing: AppError.helperStopped)
        }
    }

    // ── Lines ────────────────────────────────────────────────────────────────
    private func send<Request: BackendRequest>(_ request: Request) async throws -> Request.Result {
        let id = nextID
        nextID += 1
        let method = Request.method
        let line = try Self.line(for: request, id: id)
        let started = ContinuousClock.now
        Log.wire.debug("→ \(method, privacy: .public) #\(id)")
        let raw: Data
        do {
            raw = try await withCheckedThrowingContinuation { cont in
                guard let input else {
                    cont.resume(throwing: AppError.helperStopped)
                    return
                }
                pending[id] = cont
                do {
                    try input.write(contentsOf: line)
                } catch {
                    pending[id] = nil
                    cont.resume(throwing: error)
                }
            }
        } catch {
            Log.wire.error("""
                ✕ \(method, privacy: .public) #\(id) failed after \(Self.milliseconds(since: started), format: .fixed(precision: 1)) ms: \
                \(error.localizedDescription, privacy: .private)
                """)
            throw error
        }
        Log.wire.info("← \(method, privacy: .public) #\(id) in \(Self.milliseconds(since: started), format: .fixed(precision: 1)) ms")
        do {
            return try Self.result(Request.Result.self, from: raw, decoder: decoder)
        } catch {
            Log.wire.error("Couldn't decode the \(method, privacy: .public) #\(id) reply: \(String(describing: error), privacy: .private)")
            throw error
        }
    }

    private func receive(_ line: String) {
        let data = Data(line.utf8)
        guard let message = try? decoder.decode(Incoming.self, from: data) else {
            Log.wire.warning("Ignored a line from the helper that isn't a protocol message")
            return
        }
        if let event = message.event {
            Log.wire.info("Event \(event, privacy: .public)")
            eventSink.yield(event)
            return
        }
        guard let id = message.id, let cont = pending.removeValue(forKey: id) else {
            Log.wire.warning("Ignored a reply that matches no waiting request")
            return
        }
        if let error = message.error {
            cont.resume(throwing: AppError.backend(error))
            return
        }
        cont.resume(returning: data)
    }

    private static func milliseconds(since start: ContinuousClock.Instant) -> Double {
        let elapsed = start.duration(to: .now).components
        return Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15
    }
}
