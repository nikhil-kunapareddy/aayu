import Foundation

/// Settings keys and defaults. The views bind them with @AppStorage; the model
/// reads them from UserDefaults when it talks to the backend.
enum Pref {
    static let folder = "folder"               // Zepp export folder (a path)
    static let units = "units"                 // Units
    static let defaultRange = "defaultRange"   // DefaultRange
    static let autoReload = "autoReload"       // Bool
    static let appearance = "appearance"       // Appearance
    static let bedtime = "bedtime"             // ClockTime: the sleep score's target bedtime
    static let wakeTime = "wakeTime"           // ClockTime: …and wake time

    /// Registered at launch, so a fresh install reads these.
    static var defaults: [String: Any] {
        [folder: "", units: Units.lbs.rawValue, defaultRange: DefaultRange.month.rawValue, autoReload: true,
         appearance: Appearance.light.rawValue, bedtime: ClockTime.bedtime.rawValue,
         wakeTime: ClockTime.wakeTime.rawValue]
    }
}

/// Weight units. The raw values are what's stored and what the backend expects.
enum Units: String, CaseIterable, Codable, Sendable {
    case lbs, kg
}

/// What the dashboard opens on: the latest month, or the last 30 days.
enum DefaultRange: String, CaseIterable, Codable, Sendable {
    case month, last30
}

/// Light, dark, or following the system (see `Theme.apply(appearance:)`).
enum Appearance: String, CaseIterable, Sendable {
    case system, light, dark
}

/// A time of day. The raw value, "HH:MM" (24-hour), is what's stored and what the backend expects.
struct ClockTime: RawRepresentable, Hashable, Codable, Sendable {
    let hour: Int     // 0–23
    let minute: Int   // 0–59

    /// The sleep score's default targets: 11:30 PM and 6:30 AM.
    static let bedtime = ClockTime(hour: 23, minute: 30)
    static let wakeTime = ClockTime(hour: 6, minute: 30)

    init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    init?(rawValue: String) {
        let parts = rawValue.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ $0.count == 2 && $0.allSatisfy { ("0"..."9").contains($0) } }),
              let hour = Int(parts[0]), let minute = Int(parts[1]), hour < 24, minute < 60 else { return nil }
        self.init(hour: hour, minute: minute)
    }

    var rawValue: String { String(format: "%02d:%02d", hour, minute) }

    /// The time of day of `date` (for a DatePicker).
    init(_ date: Date, timeZone: TimeZone = .autoupdatingCurrent) {
        let parts = Self.calendar(timeZone).dateComponents([.hour, .minute], from: date)
        self.init(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }

    /// This time on 1 January 2001, a day with no clock change (for a DatePicker).
    func date(timeZone: TimeZone = .autoupdatingCurrent) -> Date {
        Self.calendar(timeZone).date(from: DateComponents(year: 2001, month: 1, day: 1, hour: hour, minute: minute))
            ?? .distantPast
    }

    private static func calendar(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}
