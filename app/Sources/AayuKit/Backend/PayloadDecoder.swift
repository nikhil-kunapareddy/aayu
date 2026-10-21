import Foundation

/// Decodes what the backend sends. Keys arrive in snake_case; timestamps as
/// naive local ISO strings ("2026-05-31T23:14:00"), read in the Mac's timezone
/// so a midnight stays a midnight.
enum PayloadDecoder {
    /// `timeZone` is the one timestamps are read in; tests pass a fixed one.
    static func make(timeZone: TimeZone = .current) -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = timeZone
        format.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        decoder.dateDecodingStrategy = .formatted(format)
        return decoder
    }
}
