import AppKit

extension Theme {
    /// Settings' "Appearance", applied to every window.
    @MainActor static func apply(appearance: Appearance) {
        NSApp.appearance = switch appearance {
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        case .system: nil   // follow the system
        }
    }
}
