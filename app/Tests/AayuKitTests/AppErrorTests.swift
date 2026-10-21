import Foundation
import Testing
@testable import AayuKit

@Suite("AppError")
struct AppErrorTests {
    static let all: [AppError] = AppError.Code.allCases.map { .backend(code: $0, message: "Backend text.") } + [
        .backend(code: nil, message: "Backend text."), .helperStopped, .crashed(stops: 4),
        .helperUnavailable(details: "No such file"), .timedOut(method: "dashboard", limit: .seconds(30)),
        .protocolError(details: "The helper sent a line that isn't a protocol message (8 bytes)."),
        .badReply(method: "dashboard", details: "keyNotFound"), .unexpected(details: "Odd"),
    ]

    @Test(arguments: all)
    func everyErrorSaysWhatHappenedAndWhatToDo(_ error: AppError) throws {
        #expect(!error.title.isEmpty)
        let message = try #require(error.errorDescription)
        let suggestion = try #require(error.recoverySuggestion)
        #expect(message.hasSuffix(".") && suggestion.hasSuffix("."))
        #expect(error.localizedDescription == message)
        // Raw backend or decoding text stays out of what's shown.
        for raw in ["Backend text", "No such file", "keyNotFound", "8 bytes", "Odd"] {
            #expect(!message.contains(raw) && !suggestion.contains(raw) && !error.title.contains(raw))
        }
    }

    @Test func theBackendsTextIsKeptAsDetails() {
        let error = AppError.backend(code: .unreadable, message: "Couldn't read the Sleep data in this export: bad header.")
        #expect(error.details == "Couldn't read the Sleep data in this export: bad header. [unreadable]")
        #expect(AppError.helperStopped.details == nil)
        #expect(AppError.badReply(method: "dashboard", details: "keyNotFound").details?.contains("keyNotFound") == true)
    }

    @Test func rawCodes() {
        #expect(AppError.backend(rawCode: "no_data", message: "x") == .backend(code: .noData, message: "x"))
        #expect(AppError.backend(rawCode: "something_new", message: "x") == .backend(code: nil, message: "x"))
        #expect(AppError.backend(rawCode: nil, message: "x") == .backend(code: nil, message: "x"))
    }

    /// The codes must match `Code` in backend/aayu_backend/errors.py.
    @Test func codesMatchTheBackend() throws {
        let errors = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("backend/aayu_backend/errors.py")
        let source = try String(contentsOf: errors, encoding: .utf8)
        let codeClass = try #require(source.range(of: "class Code(StrEnum):"))
        let rest = source[codeClass.upperBound...]
        let body = rest.range(of: "\nclass ").map { rest[..<$0.lowerBound] } ?? rest   // up to the next class
        let values = body.matches(of: /=\s*"([a-z_]+)"/).map { String($0.output.1) }
        #expect(Set(values) == Set(AppError.Code.allCases.map(\.rawValue)))
        #expect(values.count == AppError.Code.allCases.count)
    }

    @Test func folderErrorsPointAtTheFolder() {
        #expect(AppError.backend(code: .noData, message: "x").suggestsChoosingFolder)
        #expect(AppError.backend(code: .folderMissing, message: "x").suggestsChoosingFolder)
        #expect(!AppError.backend(code: .internal, message: "x").suggestsChoosingFolder)
        #expect(!AppError.helperStopped.suggestsChoosingFolder)
        #expect(!AppError.timedOut(method: "dashboard", limit: .seconds(30)).suggestsChoosingFolder)
    }

    @Test func crashCountsAgreeInNumber() throws {
        let one = try #require(AppError.crashed(stops: 1).errorDescription)
        let four = try #require(AppError.crashed(stops: 4).errorDescription)
        guard Locale.current.language.languageCode == .english else { return }   // inflection is per language
        #expect(one.contains("1 time ") && !one.contains("^["))
        #expect(four.contains("4 times "))
    }

    @Test func otherErrorsAreWrapped() {
        struct Odd: Error {}
        let decoding = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Bad JSON"))
        guard case .badReply(_, let details) = AppError(decoding) else { Issue.record("expected .badReply"); return }
        #expect(details.contains("Bad JSON"))
        guard case .unexpected = AppError(Odd()) else { Issue.record("expected .unexpected"); return }
        #expect(AppError(AppError.helperStopped) == .helperStopped)
    }

    @Test func aFolderStatusCarriesItsFailure() throws {
        let status = try Sample.decoder.decode(FolderStatus.self, from: Data(#"""
            {"exists":true,"found":[],"total":6,"error":"No Zepp data in /x.","error_code":"no_data"}
            """#.utf8))
        #expect(status.failure == .backend(code: .noData, message: "No Zepp data in /x."))
        #expect(Sample.loaded.failure == nil)
    }
}
