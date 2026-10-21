import SwiftUI

/// Colors, type, spacing and formatting — the one place to restyle the app.
///
/// The look: a deep-navy header with a frosted Sleep Score panel, over a pale
/// page of white cards (in Dark appearance, a deeper navy page of navy cards).
/// Sleep stages run deep blue → sky → lavender, with a warm peach for "Awake".
enum Theme {
    // ── Palette ──────────────────────────────────────────────────────────────
    // `rgb(light, dark)` colors follow the appearance; the header is dark in both.
    static let night  = rgb(0x0B1437)   // header, top
    static let dusk   = rgb(0x1C2A6E)   // header, bottom
    static let violet = rgb(0x7C6CF5)
    static let blue   = rgb(0x2F5BEA, 0x4F7BF7)   // primary data color
    static let navy   = rgb(0x13235B, 0x3D55C4)
    static let sky    = rgb(0x7EA6F8)
    static let mist   = rgb(0x9DB7F5)

    static let page   = rgb(0xF3F5FA, 0x080D22)   // behind the cards
    static let card   = rgb(0xFFFFFF, 0x121A38)
    static let border = rgb(0xE5E9F2, 0x222B4F)
    static let ink    = rgb(0x111827, 0xE8ECF7)   // primary text
    static let sub    = rgb(0x6B7280, 0x8E98B8)   // secondary text, axis labels
    static let grid   = rgb(0xEAEDF3, 0x222A49)
    static let up     = rgb(0x16A34A, 0x34D399)   // a change for the better
    static let down   = rgb(0xEA580C, 0xFB923C)   // a change for the worse
    static let upOnDark = rgb(0x6EE7B7)

    static let header = LinearGradient(colors: [night, dusk], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let panel = Color.white.opacity(0.05)          // frosted panel on the header
    static let panelStroke = Color.white.opacity(0.12)
    static let ring = AngularGradient(colors: [rgb(0xC4B5FD), rgb(0x818CF8), blue, rgb(0xC4B5FD)], center: .center)

    /// Sleep stages, deepest first, with color and hypnogram level (Awake on top).
    /// Blues lighten as sleep gets shallower; Awake is neutral — near-white on
    /// dark, slate on white.
    static let stages: [(name: String, color: Color, level: Double)] = [
        ("Deep", rgb(0x24477B, 0x2C5594), 0), ("REM", rgb(0x6FCBFF), 2), ("Light", rgb(0x448DC2), 1),
        ("Awake", rgb(0x8D97A8, 0xF2F3F5), 3),
    ]
    static func stageColor(_ name: String) -> Color { stages.first { $0.name == name }?.color ?? sub }
    static func stageLevel(_ name: String) -> Double { stages.first { $0.name == name }?.level ?? 0 }

    static let workoutTypes: [(name: String, color: Color)] = [("Strength", navy), ("Running", sky)]

    // KPI tile icons: SF Symbol and badge color.
    static let steps  = (icon: "shoeprints.fill", color: rgb(0x34C38F))
    static let sleep  = (icon: "bed.double.fill", color: rgb(0x8B7CF6))
    static let heart  = (icon: "heart.fill", color: rgb(0xF26D6D))
    static let scale  = (icon: "scalemass.fill", color: rgb(0x5B8DEF))

    // ── Shape and spacing ────────────────────────────────────────────────────
    static let gap: CGFloat = 16          // between cards
    static let inset: CGFloat = 28        // page padding
    static let cardRadius: CGFloat = 16
    static let panelRadius: CGFloat = 20

    // ── Formatting ───────────────────────────────────────────────────────────
    /// Picker label for 'YYYY-MM' ("May 2026") or 'last30'.
    static func rangeLabel(_ value: String) -> String {
        if value == "last30" { return "Last 30 days" }
        guard let date = month(value) else { return value }
        return date.formatted(.dateTime.month(.wide).year())
    }

    /// "for May 2026" / "for the last 30 days" — the header subtitle's tail.
    static func rangePhrase(_ value: String) -> String {
        value == "last30" ? "the last 30 days" : rangeLabel(value)
    }

    /// 'YYYY-MM-DD' (a sleep night) → Date.
    static func day(_ value: String) -> Date? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private static func month(_ value: String) -> Date? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1]))
    }

    /// 125 → "2h 5m".
    static func duration(minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    static func percent(_ share: Double) -> String {
        share.formatted(.percent.precision(.fractionLength(1)))
    }

    static func dayAfter(_ date: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: 1, to: date)!
    }

    /// X-axis ticks for start…end: the first and last day, plus one every
    /// `everyDays` between (dropping any that crowd the last). Ticks sit at noon
    /// so they line up under day-wide bars.
    static func dayTicks(from start: Date, to end: Date, everyDays: Int) -> [Date] {
        let cal = Calendar.current
        var days = [start]
        var t = cal.date(byAdding: .day, value: everyDays, to: start)!
        while (cal.dateComponents([.day], from: t, to: end).day ?? 0) >= 7 {
            days.append(t)
            t = cal.date(byAdding: .day, value: everyDays, to: t)!
        }
        days.append(end)
        return days.map { $0.addingTimeInterval(12 * 3600) }
    }

    /// Weeks run Monday–Sunday, as in the backend's week bucketing.
    static let mondayCalendar: Calendar = {
        var cal = Calendar.current
        cal.firstWeekday = 2
        return cal
    }()

    /// Settings' "Appearance" ("system" | "light" | "dark"), applied to every window.
    static func apply(appearance: String) {
        NSApp.appearance = switch appearance {
        case "light": NSAppearance(named: .aqua)
        case "dark": NSAppearance(named: .darkAqua)
        default: nil   // follow the system
        }
    }

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

extension View {
    /// A white (in Dark, navy) card on the page.
    func card(padding inset: CGFloat = 20) -> some View {
        padding(inset)
            .background(Theme.card, in: .rect(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border))
            .shadow(color: Theme.night.opacity(0.04), radius: 8, y: 2)
    }

    /// A frosted shape on the dark header.
    func frosted<S: InsettableShape>(_ shape: S) -> some View {
        background(Theme.panel, in: shape).overlay(shape.strokeBorder(Theme.panelStroke))
    }
}

/// A small colored dot, for legends.
struct Swatch: View {
    let color: Color
    var size: CGFloat = 9

    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
    }
}

/// "↗ +12% vs April" — a change, green when it's an improvement.
struct ChangeLabel: View {
    let text: String
    let change: Double         // sign gives the arrow
    let higherIsBetter: Bool?  // nil: no judgment (shown gray)

    var body: some View {
        Label(text, systemImage: change > 0 ? "arrow.up.right" : change < 0 ? "arrow.down.right" : "arrow.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
    }

    private var color: Color {
        guard let higherIsBetter, change != 0 else { return Theme.sub }
        return (change > 0) == higherIsBetter ? Theme.up : Theme.down
    }

    /// "+0.6", "−3", "±0" — signed, with a real minus sign.
    static func signed(_ value: Double, decimals: Int = 0) -> String {
        let magnitude = abs(value).formatted(.number.precision(.fractionLength(decimals)))
        return (value > 0 ? "+" : value < 0 ? "−" : "±") + magnitude
    }
}

/// The Aayu mark — drawn from the app icon itself, so the two never drift apart.
struct AayuLogo: View {
    var size: CGFloat = 40

    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}
