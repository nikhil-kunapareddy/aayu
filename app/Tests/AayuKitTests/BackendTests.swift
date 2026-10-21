import Foundation
import Testing
@testable import AayuKit

/// `Backend` against real child processes: small shell scripts standing in
/// for the Python helper (see `ScriptHelper`).
@Suite("Backend pipe", .timeLimit(.minutes(1)))
struct BackendTests {
    /// Short limits so the tests run quickly; nothing times out unless listed.
    private func backend(_ helper: ScriptHelper, timeouts: [String: Duration] = [:],
                         restartLimit: Int = 3) -> Backend {
        Backend(helper: helper.url, decoder: Sample.decoder,
                policy: .init(timeouts: timeouts, restartLimit: restartLimit, restartWindow: .seconds(60),
                              backoff: .milliseconds(1)))
    }

    private func expectProtocolError<T: Sendable>(_ task: Task<T, any Error>) async {
        do {
            _ = try await task.value
            Issue.record("expected a protocol error")
        } catch AppError.protocolError {
        } catch {
            Issue.record("expected a protocol error, got \(error)")
        }
    }

    @Test func repliesAreMatchedToTheirRequests() async throws {
        let helper = try ScriptHelper.answering()
        let backend = backend(helper)
        let status = try await backend.call(StatusRequest(folder: "/x"))
        #expect(status.exists && status.found == ["Sleep"] && status.error == nil)
        _ = try await backend.call(WatchRequest(enabled: true))
        #expect(try helper.received().map(\.request) == ["status /x", "watch true"])
        await backend.stop()
    }

    @Test func errorRepliesCarryTheirCode() async throws {
        let helper = try ScriptHelper("""
            while IFS= read -r line; do
              \(ScriptHelper.readID)
              printf '{"id":%s,"error":"No folder is open.","code":"no_folder"}\\n' "$id"
            done
            """)
        let backend = backend(helper)
        await #expect(throws: AppError.backend(code: .noFolder, message: "No folder is open.")) {
            try await backend.call(ReloadRequest())
        }
        await backend.stop()
    }

    @Test func aSlowReplyTimesOut() async throws {
        let helper = try ScriptHelper("while IFS= read -r line; do :; done")   // never answers
        let backend = backend(helper, timeouts: [StatusRequest.method: .milliseconds(150)])
        await #expect(throws: AppError.timedOut(method: "status", limit: .milliseconds(150))) {
            try await backend.call(StatusRequest(folder: "/x"))
        }
        await backend.stop()
    }

    @Test func aLateReplyIsNotTakenForTheNextOne() async throws {
        // Answers in order, but `status` only after half a second.
        let helper = try ScriptHelper.answering(extra: #"case "$line" in *'"method":"status"'*) sleep 0.5 ;; esac"#)
        let backend = backend(helper, timeouts: [StatusRequest.method: .milliseconds(100)])
        await #expect(throws: AppError.timedOut(method: "status", limit: .milliseconds(100))) {
            try await backend.call(StatusRequest(folder: "/x"))
        }
        // The late status reply (#1) arrives first and must be dropped; reload (#2) gets its own.
        let reload = try await backend.call(ReloadRequest())
        #expect(reload.exists)
        await backend.stop()
    }

    @Test func cancellingACallEndsItAtOnce() async throws {
        let helper = try ScriptHelper("while IFS= read -r line; do :; done")   // never answers
        let backend = backend(helper)
        let call = Task { try await backend.call(StatusRequest(folder: "/x")) }
        try await Task.sleep(for: .milliseconds(200))
        call.cancel()
        await #expect(throws: CancellationError.self) { try await call.value }
        await backend.stop()
    }

    @Test func aCancelledOpenRestartsTheHelperAndItsExitIsIgnored() async throws {
        // Never answers `open` (as if held by a privacy prompt); answers the rest slowly,
        // so the stopped helper's exit arrives while the new one's request waits.
        let helper = try ScriptHelper.answering(extra: """
            case "$line" in
              *'"method":"open"'*) continue ;;
              *) sleep 0.3 ;;
            esac
            """)
        let backend = backend(helper)
        let open = Task { try await backend.call(OpenRequest(folder: "/stuck")) }
        try await helper.waitForRequests(1)
        open.cancel()
        await #expect(throws: CancellationError.self) { try await open.value }

        let status = try await backend.call(StatusRequest(folder: "/x"))
        #expect(status.exists)
        let received = try helper.received()
        #expect(received.map(\.request) == ["open /stuck", "status /x"])   // the cancelled open isn't replayed
        #expect(Set(received.map(\.pid)).count == 2)
        await backend.stop()
    }

    @Test func garbageFailsEveryWaitingCall() async throws {
        let helper = try ScriptHelper("""
            IFS= read -r a; IFS= read -r b
            echo 'not json'
            while IFS= read -r line; do :; done
            """)
        let backend = backend(helper)
        let first = Task { try await backend.call(StatusRequest(folder: "/a")) }
        let second = Task { try await backend.call(StatusRequest(folder: "/b")) }
        await expectProtocolError(first)
        await expectProtocolError(second)
        await backend.stop()
    }

    @Test func aReplyWithoutAnIdFailsEveryWaitingCall() async throws {
        let helper = try ScriptHelper("""
            IFS= read -r a; IFS= read -r b
            echo '{"id":null,"error":"Bad request.","code":"bad_request"}'
            while IFS= read -r line; do :; done
            """)
        let backend = backend(helper)
        let first = Task { try await backend.call(StatusRequest(folder: "/a")) }
        let second = Task { try await backend.call(StatusRequest(folder: "/b")) }
        await expectProtocolError(first)
        await expectProtocolError(second)
        await backend.stop()
    }

    @Test func aRelaunchedHelperGetsTheLastOpenAndWatchFirst() async throws {
        let helper = try ScriptHelper.answering(extra: #"case "$line" in *'"folder":"/crash"'*) exit 1 ;; esac"#)
        let backend = backend(helper)
        _ = try await backend.call(WatchRequest(enabled: true))
        _ = try await backend.call(OpenRequest(folder: "/z"))
        await #expect(throws: AppError.helperStopped) { try await backend.call(StatusRequest(folder: "/crash")) }
        _ = try await backend.call(StatusRequest(folder: "/after"))
        _ = try await backend.call(OpenRequest(folder: "/new"))
        await #expect(throws: AppError.helperStopped) { try await backend.call(StatusRequest(folder: "/crash")) }
        _ = try await backend.call(OpenRequest(folder: "/y"))   // its own open isn't replayed first

        let received = try helper.received()
        #expect(received.map(\.request) == [
            "watch true", "open /z", "status /crash",
            "watch true", "open /z", "status /after", "open /new", "status /crash",
            "watch true", "open /y",
        ])
        #expect(Set(received.map(\.pid)).count == 3)
        await backend.stop()
    }

    @Test func aHelperThatKeepsExitingIsGivenUpOn() async throws {
        let helper = try ScriptHelper("""
            echo start >> "$LOG.starts"
            IFS= read -r line
            exit 1
            """)
        let backend = backend(helper, restartLimit: 2)
        await #expect(throws: AppError.helperStopped) { try await backend.call(StatusRequest(folder: "/x")) }
        await #expect(throws: AppError.helperStopped) { try await backend.call(StatusRequest(folder: "/x")) }
        await #expect(throws: AppError.crashed(stops: 3)) { try await backend.call(StatusRequest(folder: "/x")) }
        await #expect(throws: AppError.crashed(stops: 3)) { try await backend.call(StatusRequest(folder: "/x")) }
        let starts = try String(contentsOf: helper.log.appendingPathExtension("starts"), encoding: .utf8)
        #expect(starts.split(separator: "\n").count == 3)   // no fourth launch
    }

    @Test func aMissingHelperIsReported() async throws {
        let backend = Backend(helper: URL(fileURLWithPath: "/nonexistent/aayu-backend"))
        do {
            _ = try await backend.call(StatusRequest(folder: "/x"))
            Issue.record("expected the launch to fail")
        } catch AppError.helperUnavailable {
        }
    }

    /// Many helpers at once (as after several relaunches, or in parallel tests)
    /// must not stall each other: reading their pipes mustn't hold threads.
    @Test func manyHelpersAtOnce() async throws {
        let helper = try ScriptHelper.answering()
        let backends = (0..<24).map { _ in backend(helper) }
        try await withThrowingTaskGroup(of: Bool.self) { group in
            for backend in backends {
                group.addTask { try await backend.call(StatusRequest(folder: "/x")).exists }
            }
            for try await exists in group { #expect(exists) }
        }
        for backend in backends { await backend.stop() }
    }

    @Test func pipeLinesSplitOnNewlines() {
        var buffer = Data("one\ntwo\nthr".utf8)
        #expect(PipeLines.split(&buffer) == ["one", "two"])
        #expect(buffer == Data("thr".utf8))
        buffer.append(Data("ee\n\n".utf8))
        #expect(PipeLines.split(&buffer) == ["three", ""])
        #expect(buffer.isEmpty)
    }

    @Test func policy() {
        let standard = Backend.Policy.standard
        #expect(standard.timeouts[OpenRequest.method] == nil)   // may wait on a privacy prompt
        #expect(standard.timeouts[StatusRequest.method] == .seconds(10))
        #expect(standard.timeouts[WatchRequest.method] == .seconds(10))
        #expect(standard.timeouts[DashboardRequest.method] == .seconds(30))
        #expect(standard.restartLimit == 3 && standard.restartWindow == .seconds(60))
        #expect([1, 2, 3, 4].map(standard.pause(afterExit:))
                == [.zero, .milliseconds(500), .seconds(1), .seconds(2)])
    }
}
