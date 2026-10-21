import os

/// Unified-logging channels. Watch them with
/// `log stream --level info --predicate 'subsystem == "io.github.nikhil-kunapareddy.aayu"'`.
///
/// Method names, request ids, timings, pids and exit statuses are logged as
/// public. Anything that can carry personal data — folder paths, error text,
/// the helper's own output — stays private (redacted unless private data is
/// enabled); request and reply payloads are never logged.
enum Log {
    static let subsystem = "io.github.nikhil-kunapareddy.aayu"

    /// App lifecycle.
    static let app = Logger(subsystem: subsystem, category: "app")
    /// The helper process: launch, exit, relaunch.
    static let backend = Logger(subsystem: subsystem, category: "backend")
    /// Requests and replies on the JSON-lines pipe (category "protocol").
    static let wire = Logger(subsystem: subsystem, category: "protocol")
    /// Dashboard state: failures and dropped replies.
    static let model = Logger(subsystem: subsystem, category: "model")
    /// The helper's stderr, a line per entry.
    static let helper = Logger(subsystem: subsystem, category: "helper")
}
