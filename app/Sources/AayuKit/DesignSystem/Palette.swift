import SwiftUI

/// Colors, type, spacing and formatting — the one place to restyle the app.
/// The namespace is spread over DesignSystem/: the palette (here), Typography,
/// Metrics, Format, Appearance, Modifiers, ButtonStyles and Components.
///
/// The look: a deep-navy header with a frosted Sleep Score panel, over a pale
/// page of white cards (in Dark appearance, a deeper navy page of navy cards).
/// Sleep stages run deep blue → sky → lavender, with a warm peach for "Awake".
///
/// Contrast (WCAG 2.1): text colors are ≥ 4.5:1 on the card they sit on, chart
/// marks and controls ≥ 3:1, in both appearances (`ContrastTests` checks them).
enum Theme {
    // ── Palette ──────────────────────────────────────────────────────────────
    // `rgb(light, dark)` colors follow the appearance; the header is dark in both.
    static let night  = rgb(0x0B1437)   // header, top
    static let dusk   = rgb(0x1C2A6E)   // header, bottom
    static let violet = rgb(0x7C6CF5)
    static let blue   = rgb(0x2F5BEA, 0x4F7BF7)   // primary data color
    static let navy   = rgb(0x13235B, 0x5A73E0)   // Strength
    static let sky    = rgb(0x5B8DEF, 0x7EA6F8)   // Running; lighter in Dark to stand apart from Strength
    static let mist   = rgb(0x6E8FE8)             // the raw Calories line, under its average

    static let page   = rgb(0xF3F5FA, 0x080D22)   // behind the cards
    static let card   = rgb(0xFFFFFF, 0x121A38)
    static let border = rgb(0xE5E9F2, 0x222B4F)
    static let ink    = rgb(0x111827, 0xE8ECF7)   // primary text
    static let sub    = rgb(0x6B7280, 0x8E98B8)   // secondary text, axis labels
    static let grid   = rgb(0xEAEDF3, 0x222A49)
    static let up     = rgb(0x15803D, 0x34D399)   // a change for the better
    static let down   = rgb(0xC2410C, 0xFB923C)   // a change for the worse
    static let upOnDark = rgb(0x6EE7B7)           // the same, on the header
    static let downOnDark = rgb(0xFDBA74)
    static let warning = rgb(0xB45309, 0xFBBF24)   // a problem that needs attention (status banner)
    static let dot    = rgb(0x848C9C, 0x5A6488)   // an inactive pager dot
    static let hoverRule = sub.opacity(0.5)       // the line under the pointer on a chart

    static let header = LinearGradient(colors: [night, dusk], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let headerRule = Color.white.opacity(0.08)    // under the header, in Dark
    static let panel = Color.white.opacity(0.05)          // frosted panel on the header
    static let panelStroke = Color.white.opacity(0.12)
    static let ring = AngularGradient(colors: [rgb(0xC4B5FD), rgb(0x818CF8), blue, rgb(0xC4B5FD)], center: .center)

    /// Sleep stages, deepest first, with color and hypnogram level (Awake on top).
    /// Blues lighten as sleep gets shallower; Awake is neutral — near-white on
    /// dark, slate on white.
    static let stages: [(name: String, color: Color, level: Double)] = [
        ("Deep", rgb(0x24477B, 0x3A68B0), 0), ("REM", rgb(0x6FCBFF), 2), ("Light", rgb(0x448DC2), 1),
        ("Awake", rgb(0x8D97A8, 0xF2F3F5), 3),
    ]
    /// The stages as the hypnogram stacks them, top to bottom: Awake, REM, Light, Deep.
    static var stagesByDepth: [(name: String, color: Color, level: Double)] {
        stages.sorted { $0.level > $1.level }
    }
    static func stageColor(_ name: String) -> Color { stages.first { $0.name == name }?.color ?? sub }
    static func stageLevel(_ name: String) -> Double { stages.first { $0.name == name }?.level ?? 0 }

    static let workoutTypes: [(name: String, color: Color)] = [("Strength", navy), ("Running", sky)]

    // KPI tile icons: SF Symbol and badge color.
    static let steps  = (icon: "shoeprints.fill", color: rgb(0x34C38F))
    static let sleep  = (icon: "bed.double.fill", color: rgb(0x8B7CF6))
    static let heart  = (icon: "heart.fill", color: rgb(0xF26D6D))
    static let scale  = (icon: "scalemass.fill", color: rgb(0x5B8DEF))

    // ── Building colors ──────────────────────────────────────────────────────
    private static func rgb(_ hex: Int) -> Color {
        Color(nsColor: nsColor(hex))
    }

    /// A color with a value for each appearance.
    private static func rgb(_ light: Int, _ dark: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            nsColor(appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        })
    }

    private static func nsColor(_ hex: Int) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
