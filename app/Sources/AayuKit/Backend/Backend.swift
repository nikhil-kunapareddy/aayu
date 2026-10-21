import Foundation
import os
import Synchronization

/// The Python backend, run as a hidden helper process.
///
/// We exchange one JSON object per line over its stdin/stdout (see
/// backend/aayu_backend/server.py): each request carries an `id` that the reply
/// echoes; lines with an `event` are pushed by the backend (auto-reload). No
/// network port is involved.
///
/// Resilience:
/// - Every method but `open` has a time limit (`Policy.timeouts`); `open` can
///   sit behind a macOS privacy prompt for as long as the person takes.
/// - A cancelled call returns at once with `CancellationError`. A cancelled
///   `open` also stops the helper — it may be stuck on that prompt — so the
///   next call starts a fresh one.
/// - A line that isn't a protocol message, or a reply without an id, fails
///   every waiting call with `AppError.protocolError`.
/// - If the helper dies, the calls waiting on it fail with
///   `AppError.helperStopped`; the next call relaunches it (after a short,
///   growing pause) and first replays the last `open`/`watch`. More than
///   `Policy.restartLimit` exits within `Policy.restartWindow` and it stays
///   down: every call then fails with `AppError.crashed`.
///
/// The helper's stderr is forwarded line by line to the unified log and to the
/// app's own stderr (which `make run` writes to its log file).
actor Backend: BackendClient {
    /// The helper inside Aayu.app: the frozen backend in release builds, a
    /// script running the backend from source in `make run` builds.
    static let bundledHelper = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/backend/aayu-backend")

    /// Time limits, and how a helper that keeps exiting is restarted.
    struct Policy: Sendable {
        /// How long each method waits for its reply, counted from when its
        /// line is written. Methods not listed wait for ever.
        var timeouts: [String: Duration]
        /// Exits tolerated within `restartWindow`; one more and the helper stays down.
        var restartLimit: Int
        var restartWindow: Duration
        /// The pause before the second relaunch in a window, doubling for
        /// each one after; the first relaunch is immediate.
        var backoff: Duration

        /// `open` has no limit (see the type's comment). `reload` re-reads
        /// every CSV, as `open` does, so it gets as long as `dashboard`.
        static let standard = Policy(
            timeouts: [StatusRequest.method: .seconds(10), WatchRequest.method: .seconds(10),
                       ReloadRequest.method: .seconds(30), DashboardRequest.method: .seconds(30)],
            restartLimit: 3, restartWindow: .seconds(60), backoff: .milliseconds(500))

        /// The pause before relaunching after the `n`th exit in the window (n ≥ 1).
        func pause(afterExit n: Int) -> Duration {
            n <= 1 ? .zero : backoff * (1 << min(n - 2, 16))
        }
    }

    /// Methods whose last request is replayed to a relaunched helper, in this order.
    private static let replayed = [WatchRequest.method, OpenRequest.method]

    /// The live helper, so `terminateHelper()` can reach it from outside the actor.
    private static let live = Mutex<Process?>(nil)
    /// Set when the app quits, so the helper's exit then isn't reported as a crash.
    private static let quitting = Atomic<Bool>(false)

    nonisolated let events: AsyncStream<String>
    private let eventSink: AsyncStream<String>.Continuation
    private let helper: URL
    private let decoder: JSONDecoder
    private let policy: Policy

    /// A request whose reply hasn't come yet.
    private struct Pending {
        let method: String
        let sent: ContinuousClock.Instant
        /// Who awaits the reply; nil for a replayed request, whose reply is only logged.
        let caller: CheckedContinuation<Data, any Error>?
        var timer: Task<Void, Never>?
    }

    private var process: Process?
    private var input: FileHandle?
    private var generation = 0                // bumped per launch; tags each helper's callbacks
    private var launches = 0
    private var nextID = 1
    private var pending: [Int: Pending] = [:]
    private var abandoned: Set<Int> = []      // timed out or cancelled: a late reply is dropped quietly
    private var replay: [String: any BackendRequest] = [:]   // last "open" / "watch"
    private var exits: [ContinuousClock.Instant] = []        // unexpected exits within the window
    private var relaunchAt: ContinuousClock.Instant?         // not before this, after an exit
    private var gaveUp: AppError?                            // set once the helper has exited too often

    init(helper: URL = Backend.bundledHelper, decoder: JSONDecoder = PayloadDecoder.make(),
         policy: Policy = .standard) {
        self.helper = helper
        self.decoder = decoder
        self.policy = policy
        (events, eventSink) = AsyncStream.makeStream(of: String.self)
    }

    deinit {
        eventSink.finish()
    }

    /// Send `request` and decode its result, launching the helper first if
    /// needed. Throws `CancellationError` if the calling task is cancelled,
    /// an `AppError` for everything else.
    func call<Request: BackendRequest>(_ request: Request) async throws -> Request.Result {
        try await ensureHelper(for: Request.method)
        if Self.replayed.contains(Request.method) {
            replay[Request.method] = request
        }
        let raw = try await send(request)
        do {
            return try Self.result(Request.Result.self, from: raw, decoder: decoder)
        } catch {
            Log.wire.error("Couldn't decode the \(Request.method, privacy: .public) reply: \(String(describing: error), privacy: .private)")
            throw AppError.badReply(method: Request.method, details: String(describing: error))
        }
    }

    /// Stop this backend's helper (tests; the app uses `terminateHelper()` at quit).
    func stop() {
        retire(because: "it was asked to stop")
    }

    /// Stop the helper when the app quits. It normally exits by itself once
    /// its stdin closes, but not while blocked — e.g. waiting on the macOS
    /// privacy prompt for a folder in ~/Documents.
    static func terminateHelper() {
        quitting.store(true, ordering: .relaxed)
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
        let code: String?
    }

    // ── Process ──────────────────────────────────────────────────────────────
    /// Make sure a helper is running, relaunching one (and replaying the last
    /// `open`/`watch`, except `method`'s own) if the last one exited.
    private func ensureHelper(for method: String) async throws {
        while process == nil {
            if let gaveUp { throw gaveUp }
            if let relaunchAt, relaunchAt > .now {
                Log.backend.info("Waiting before relaunching the helper")
                try await Task.sleep(until: relaunchAt, clock: .continuous)
                continue   // another call may have relaunched it meanwhile
            }
            relaunchAt = nil
            try launch()
            replayPrevious(except: method)
        }
    }

    private func launch() throws {
        signal(SIGPIPE, SIG_IGN)   // a dead helper must surface as a write error, not kill the app
        let p = Process()
        p.executableURL = helper
        let toBackend = Pipe(), fromBackend = Pipe(), helperLog = Pipe()
        p.standardInput = toBackend
        p.standardOutput = fromBackend
        p.standardError = helperLog
        generation += 1
        let generation = generation
        p.terminationHandler = { [weak self] p in
            let pid = p.processIdentifier, status = p.terminationStatus, reason = p.terminationReason
            Task { await self?.exited(generation: generation, pid: pid, status: status, reason: reason) }
        }
        do {
            try p.run()
        } catch {
            Log.backend.error("""
                Couldn't launch the helper at \(self.helper.path, privacy: .private): \
                \(error.localizedDescription, privacy: .private)
                """)
            throw AppError.helperUnavailable(details: error.localizedDescription)
        }
        launches += 1
        let verb = launches == 1 ? "Launched" : "Relaunched"
        Log.backend.notice("\(verb, privacy: .public) helper, pid \(p.processIdentifier)")
        process = p
        Self.live.withLock { $0 = p }
        input = toBackend.fileHandleForWriting

        let replies = PipeLines.stream(from: fromBackend.fileHandleForReading)
        Task { [weak self] in
            for await line in replies {
                await self?.receive(line, from: generation)
            }
            Log.wire.debug("The helper's output closed")
        }
        Self.forward(PipeLines.stream(from: helperLog.fileHandleForReading))
    }

    /// Write the last `open`/`watch` to a freshly launched helper, ahead of
    /// anything else, so it's back in the state the app left it in. Their
    /// replies are only logged; the caller's own request shows how it went.
    private func replayPrevious(except method: String) {
        for replayedMethod in Self.replayed where replayedMethod != method {
            guard let previous = replay[replayedMethod] else { continue }
            Log.backend.info("Replaying \(replayedMethod, privacy: .public) to the new helper")
            let id = takeID()
            do {
                write(try Self.line(for: previous, id: id), id: id, method: replayedMethod, caller: nil)
            } catch {
                Log.wire.error("Couldn't encode the replayed \(replayedMethod, privacy: .public): \(String(describing: error), privacy: .private)")
            }
        }
    }

    /// Pass the helper's stderr on, line by line: to the unified log (category
    /// "helper") and to our own stderr.
    private static func forward(_ stderr: AsyncStream<String>) {
        Task.detached(priority: .utility) {
            for await line in stderr {
                Log.helper.notice("\(line, privacy: .private)")
                do {
                    try FileHandle.standardError.write(contentsOf: Data((line + "\n").utf8))
                } catch {
                    Log.backend.debug("Couldn't echo the helper's stderr: \(error.localizedDescription, privacy: .private)")
                }
            }
        }
    }

    /// A helper exited. Only the current one matters: one we've already
    /// replaced (or stopped on purpose) must not take its successor down too.
    private func exited(generation: Int, pid: Int32, status: Int32, reason: Process.TerminationReason) {
        Self.live.withLock { live in
            if live?.processIdentifier == pid { live = nil }
        }
        let how = reason == .uncaughtSignal ? "signal" : "status"
        guard generation == self.generation, process != nil else {
            Log.backend.info("Earlier helper exited, pid \(pid), \(how, privacy: .public) \(status)")
            return
        }
        lost("exited, pid \(pid), \(how) \(status)")
    }

    /// The current helper is gone without being asked to go: fail what waited
    /// on it, and count the exit against the restart budget.
    private func lost(_ what: String) {
        process?.terminate()   // if it's still around (a broken pipe)
        process = nil
        input = nil
        abandoned.removeAll()
        if Self.quitting.load(ordering: .relaxed) {
            Log.backend.notice("Helper \(what, privacy: .public) as Aayu quits")
            failAll(with: AppError.helperStopped)
            return
        }
        let now = ContinuousClock.now
        exits.removeAll { $0.duration(to: now) > policy.restartWindow }
        exits.append(now)
        let error: AppError
        if exits.count > policy.restartLimit {
            error = .crashed(stops: exits.count)
            gaveUp = error
            Log.backend.fault("Helper \(what, privacy: .public): \(self.exits.count) exits in the restart window; not restarting it")
        } else {
            error = .helperStopped
            relaunchAt = now + policy.pause(afterExit: exits.count)
            Log.backend.error("Helper \(what, privacy: .public), with \(self.pending.count) request(s) waiting")
        }
        failAll(with: error)
    }

    /// Stop the current helper on purpose (not counted as a crash).
    private func retire(because reason: String) {
        guard let p = process else { return }
        Log.backend.notice("Stopping helper, pid \(p.processIdentifier): \(reason, privacy: .public)")
        process = nil
        input = nil
        abandoned.removeAll()
        Self.live.withLock { live in
            if live === p { live = nil }
        }
        p.terminate()
        failAll(with: AppError.helperStopped)
    }

    // ── Lines ────────────────────────────────────────────────────────────────
    private func takeID() -> Int {
        defer { nextID += 1 }
        return nextID
    }

    private func send<Request: BackendRequest>(_ request: Request) async throws -> Data {
        let id = takeID()
        let method = Request.method
        let line: Data
        do {
            line = try Self.line(for: request, id: id)
        } catch {
            throw AppError.unexpected(details: "Couldn't encode \(method): \(error)")
        }
        let started = ContinuousClock.now
        Log.wire.debug("→ \(method, privacy: .public) #\(id)")
        do {
            let raw = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, any Error>) in
                    if Task.isCancelled {
                        cont.resume(throwing: CancellationError())
                        return
                    }
                    write(line, id: id, method: method, caller: cont)
                }
            } onCancel: {
                Task { await self.cancel(id) }
            }
            Log.wire.info("← \(method, privacy: .public) #\(id) in \(Self.milliseconds(since: started), format: .fixed(precision: 1)) ms")
            return raw
        } catch is CancellationError {
            Log.wire.info("✕ \(method, privacy: .public) #\(id) cancelled after \(Self.milliseconds(since: started), format: .fixed(precision: 1)) ms")
            throw CancellationError()
        } catch {
            Log.wire.error("""
                ✕ \(method, privacy: .public) #\(id) failed after \(Self.milliseconds(since: started), format: .fixed(precision: 1)) ms: \
                \(String(describing: error), privacy: .private)
                """)
            throw error
        }
    }

    /// Write one request line and note who waits for its reply, with a timer
    /// if the method has a time limit.
    private func write(_ line: Data, id: Int, method: String, caller: CheckedContinuation<Data, any Error>?) {
        guard let input else {
            caller?.resume(throwing: AppError.helperStopped)
            return
        }
        var entry = Pending(method: method, sent: .now, caller: caller)
        if let limit = policy.timeouts[method] {
            entry.timer = Task { [weak self] in
                do {
                    try await Task.sleep(for: limit)
                } catch {
                    return   // cancelled: the reply came first
                }
                await self?.timedOut(id, limit: limit)
            }
        }
        pending[id] = entry
        do {
            try input.write(contentsOf: line)
        } catch {
            Log.wire.error("Couldn't write to the helper: \(error.localizedDescription, privacy: .private)")
            lost("stopped reading its input")
        }
    }

    /// Resolve request `id`, if it's still waiting. `abandon` marks a request
    /// given up on (timed out, cancelled) whose reply may still turn up.
    private func finish(_ id: Int, with result: Result<Data, any Error>, abandon: Bool = false) {
        guard let entry = pending.removeValue(forKey: id) else { return }
        entry.timer?.cancel()
        if abandon { abandoned.insert(id) }
        if let caller = entry.caller {
            caller.resume(with: result)
        } else if case .failure(let error) = result {
            Log.backend.error("The replayed \(entry.method, privacy: .public) #\(id) failed: \(String(describing: error), privacy: .private)")
        }
    }

    private func failAll(with error: any Error, abandon: Bool = false) {
        for id in pending.keys.sorted() {
            finish(id, with: .failure(error), abandon: abandon)
        }
    }

    private func timedOut(_ id: Int, limit: Duration) {
        guard let entry = pending[id] else { return }
        Log.wire.error("✕ \(entry.method, privacy: .public) #\(id) got no reply within \(limit, privacy: .public)")
        finish(id, with: .failure(AppError.timedOut(method: entry.method, limit: limit)), abandon: true)
    }

    private func cancel(_ id: Int) {
        guard let entry = pending[id] else { return }
        finish(id, with: .failure(CancellationError()), abandon: true)
        if entry.method == OpenRequest.method {
            // The helper may be held on a privacy prompt for that folder. Start
            // afresh rather than queue the next request behind it.
            replay[OpenRequest.method] = nil
            retire(because: "a cancelled open may still be holding it")
        }
    }

    private func receive(_ line: String, from generation: Int) {
        guard generation == self.generation, process != nil else {
            Log.wire.debug("Ignored a line from a helper that has been replaced")
            return
        }
        guard !line.allSatisfy(\.isWhitespace) else { return }
        let data = Data(line.utf8)
        let message: Incoming
        do {
            message = try decoder.decode(Incoming.self, from: data)
        } catch {
            protocolFailure("a line that isn't a protocol message (\(data.count) bytes)")
            return
        }
        if let event = message.event {
            Log.wire.info("Event \(event, privacy: .public)")
            eventSink.yield(event)
            return
        }
        guard let id = message.id else {
            // The backend couldn't read one of our lines far enough to find
            // its id, so there's no telling which request it was.
            protocolFailure("a reply without an id (code \(message.code ?? "none"))")
            return
        }
        guard pending[id] != nil else {
            if abandoned.remove(id) != nil {
                Log.wire.debug("Dropped the late reply to #\(id)")
            } else {
                Log.wire.warning("Ignored a reply that matches no waiting request (#\(id))")
            }
            return
        }
        if let error = message.error {
            finish(id, with: .failure(AppError.backend(rawCode: message.code, message: error)))
        } else {
            finish(id, with: .success(data))
        }
    }

    private func protocolFailure(_ what: String) {
        Log.wire.error("The helper sent \(what, privacy: .public); failing \(self.pending.count) waiting request(s)")
        failAll(with: AppError.protocolError(details: "The helper sent \(what)."), abandon: true)
    }

    private static func milliseconds(since start: ContinuousClock.Instant) -> Double {
        let elapsed = start.duration(to: .now).components
        return Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15
    }
}
