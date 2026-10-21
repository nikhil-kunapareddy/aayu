import Foundation

/// Everything that can go wrong between the app and its data, worded for the
/// person using Aayu: a short `title`, a sentence saying what happened
/// (`errorDescription`), what to do about it (`recoverySuggestion`), and the
/// raw text behind it (`details`) — the backend's own message, a decoding
/// error — which the UI only shows behind a disclosure, never as the message.
enum AppError: LocalizedError, Equatable, Sendable {
    /// The `code` of a backend error reply (and a status's `error_code`);
    /// mirrors `Code` in backend/aayu_backend/errors.py.
    enum Code: String, CaseIterable, Sendable {
        case noFolder = "no_folder"            // no export folder is open
        case folderMissing = "folder_missing"  // the open folder doesn't exist (any more)
        case noData = "no_data"                // the folder holds no usable Zepp data
        case unreadable                        // a CSV couldn't be read or parsed
        case badRequest = "bad_request"        // our request line wasn't valid
        case unknownMethod = "unknown_method"  // the method isn't in Server.METHODS
        case badParams = "bad_params"          // missing, unexpected or invalid params
        case `internal`                        // a bug in the backend; details are in its log
    }

    /// The backend answered with an error. `code` is nil when the reply had
    /// none, or one this version doesn't know; `message` is the backend's text.
    case backend(code: Code?, message: String)
    /// The helper exited, or its pipe broke, while a request waited.
    case helperStopped
    /// The helper kept exiting, so it's no longer restarted. `stops` counts
    /// the exits within the restart window.
    case crashed(stops: Int)
    /// The helper couldn't be started at all.
    case helperUnavailable(details: String)
    /// No reply to `method` within its time limit.
    case timedOut(method: String, limit: Duration)
    /// The helper sent a line that isn't a protocol message, or a reply
    /// without an id; every request waiting at the time fails with this.
    case protocolError(details: String)
    /// A reply whose result didn't decode.
    case badReply(method: String, details: String)
    /// Anything else.
    case unexpected(details: String)

    /// A backend error from the raw `code` string on the wire.
    static func backend(rawCode: String?, message: String) -> AppError {
        .backend(code: rawCode.flatMap(Code.init(rawValue:)), message: message)
    }

    /// `error` as an AppError: itself if it is one, else wrapped with its text as the details.
    init(_ error: any Error) {
        switch error {
        case let error as AppError: self = error
        case let error as DecodingError: self = .badReply(method: "?", details: String(describing: error))
        default: self = .unexpected(details: "\(type(of: error)): \(error.localizedDescription)")
        }
    }

    // ── What the UI shows ────────────────────────────────────────────────────
    /// A few words, title case: the banner's and the failure screen's heading.
    var title: String {
        switch self {
        case .backend(let code?, _):
            switch code {
            case .noFolder: String(localized: "No Folder Open")
            case .folderMissing: String(localized: "Folder Not Found")
            case .noData: String(localized: "No Zepp Data Found")
            case .unreadable: String(localized: "Can’t Read Your Export")
            case .badRequest, .unknownMethod, .badParams, .internal: String(localized: "Something Went Wrong")
            }
        case .backend(nil, _), .protocolError, .badReply, .unexpected: String(localized: "Something Went Wrong")
        case .helperStopped: String(localized: "Data Helper Stopped")
        case .crashed: String(localized: "Data Helper Keeps Stopping")
        case .helperUnavailable: String(localized: "Can’t Start the Data Helper")
        case .timedOut: String(localized: "Taking Too Long")
        }
    }

    /// One sentence: what happened.
    var errorDescription: String? {
        switch self {
        case .backend(let code?, _):
            switch code {
            case .noFolder: String(localized: "Aayu doesn’t have a Zepp export open.")
            case .folderMissing: String(localized: "Your Zepp export folder has been moved, renamed or deleted.")
            case .noData: String(localized: "This folder doesn’t contain a Zepp export.")
            case .unreadable: String(localized: "Part of this export is damaged or in a format Aayu doesn’t recognize.")
            case .badRequest, .unknownMethod, .badParams, .internal:
                String(localized: "Aayu’s data helper couldn’t complete the request.")
            }
        case .backend(nil, _): String(localized: "Aayu’s data helper couldn’t complete the request.")
        case .helperStopped: String(localized: "Aayu’s data helper stopped unexpectedly.")
        case .crashed(let stops):
            Self.inflected("Aayu’s data helper stopped ^[\(stops) time](inflect: true) within a minute, so Aayu stopped restarting it.")
        case .helperUnavailable: String(localized: "Part of Aayu is missing or damaged.")
        case .timedOut: String(localized: "Aayu’s data helper didn’t answer in time.")
        case .protocolError, .badReply: String(localized: "Aayu’s data helper sent a reply Aayu couldn’t understand.")
        case .unexpected: String(localized: "Something unexpected happened.")
        }
    }

    /// One sentence: what to do next.
    var recoverySuggestion: String? {
        switch self {
        case .backend(let code?, _):
            switch code {
            case .noFolder: String(localized: "Choose the folder you exported from the Zepp app.")
            case .folderMissing: String(localized: "Choose the folder again, or put it back where it was.")
            case .noData: String(localized: "Choose the folder that contains SLEEP, ACTIVITY, BODY and the other data folders.")
            case .unreadable: String(localized: "Export your data from the Zepp app again, then choose the new folder.")
            case .badRequest, .unknownMethod, .badParams, .internal: Self.tryAgainOrRelaunch
            }
        case .backend(nil, _), .protocolError, .badReply, .unexpected: Self.tryAgainOrRelaunch
        case .helperStopped: String(localized: "Try again — Aayu restarts it automatically.")
        case .crashed: String(localized: "Quit Aayu and open it again.")
        case .helperUnavailable: String(localized: "Reinstall Aayu, then open it again.")
        case .timedOut: String(localized: "Try again in a moment.")
        }
    }

    /// The text behind the message, for a "Details" disclosure and the log.
    /// Not localized: it's for diagnosing, not for reading as the message.
    var details: String? {
        switch self {
        case .backend(let code, let message): code.map { "\(message) [\($0.rawValue)]" } ?? message
        case .helperStopped: nil
        case .crashed(let stops): "The helper exited \(stops) times within the restart window."
        case .helperUnavailable(let details), .protocolError(let details), .unexpected(let details): details
        case .timedOut(let method, let limit): "No reply to “\(method)” within \(limit)."
        case .badReply(let method, let details): "The “\(method)” reply didn’t decode: \(details)"
        }
    }

    /// Whether choosing another folder is the likelier fix (rather than trying again).
    var suggestsChoosingFolder: Bool {
        switch self {
        case .backend(let code?, _): [.noFolder, .folderMissing, .noData, .unreadable].contains(code)
        default: false
        }
    }

    private static var tryAgainOrRelaunch: String {
        String(localized: "Try again. If it keeps happening, quit Aayu and open it again.")
    }

    /// A localized string with automatic grammar agreement applied (`^[…](inflect: true)`),
    /// which `String(localized:)` alone leaves as markup.
    private static func inflected(_ resource: LocalizedStringResource) -> String {
        String(AttributedString(localized: resource).characters)
    }
}
