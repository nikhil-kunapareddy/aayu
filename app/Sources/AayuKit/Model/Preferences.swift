import Foundation

/// Settings keys and defaults. The views bind them with @AppStorage; the model
/// reads them from UserDefaults when it talks to the backend.
enum Pref {
    static let folder = "folder"               // Zepp export folder (a path)
    static let units = "units"                 // Units
    static let defaultRange = "defaultRange"   // DefaultRange
    static let autoReload = "autoReload"       // Bool
    static let appearance = "appearance"       // Appearance

    /// Registered at launch, so a fresh install reads these.
    static var defaults: [String: Any] {
        [folder: "", units: Units.lbs.rawValue, defaultRange: DefaultRange.month.rawValue, autoReload: true,
         appearance: Appearance.light.rawValue]
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
