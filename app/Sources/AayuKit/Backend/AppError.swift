import Foundation

/// Failures the app reports itself. Others — a helper that won't launch, a
/// broken pipe, a reply that doesn't decode — surface as their own errors.
/// `errorDescription` is what the dashboard shows.
enum AppError: LocalizedError, Equatable {
    /// The backend answered with an error; its message is already user-facing.
    case backend(String)
    /// The helper exited while a request was waiting for its reply.
    case helperStopped

    var errorDescription: String? {
        switch self {
        case .backend(let message): message
        case .helperStopped: "The data helper stopped unexpectedly. Try again."
        }
    }
}
