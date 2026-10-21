import SwiftUI

extension Theme {
    // ── Shape and spacing (a 4-pt grid) ──────────────────────────────────────
    static let gap: CGFloat = 16          // between cards
    static let inset: CGFloat = 28        // page padding; the header's content lines up with it
    static let cardRadius: CGFloat = 16
    static let panelRadius: CGFloat = 20
    static let maxContentWidth: CGFloat = 1640   // page content is centred past this; the header stays full-bleed
    static let chartMinHeight: CGFloat = 320     // the chart card never gets shorter; the page scrolls instead

    // ── Layout maths ─────────────────────────────────────────────────────────
    /// Widths for a stacked bar's segments: shares of `total` less the gaps
    /// between them, with any non-empty segment at least `minimum` wide (taken
    /// from the larger ones in proportion). Empty shares get no width and no gap.
    static func segmentWidths(_ shares: [Double], total: CGFloat, spacing: CGFloat,
                              minimum: CGFloat) -> [CGFloat] {
        let shown = shares.filter { $0 > 0 }.count
        let sum = shares.reduce(0) { $0 + max($1, 0) }
        guard shown > 0, sum > 0 else { return shares.map { _ in CGFloat(0) } }
        let available = max(0, total - spacing * CGFloat(shown - 1))
        var widths: [CGFloat] = shares.map { $0 > 0 ? available * CGFloat($0 / sum) : 0 }
        let small = widths.indices.filter { widths[$0] > 0 && widths[$0] < minimum }
        let largeTotal = widths.indices.filter { widths[$0] >= minimum }.reduce(0) { $0 + widths[$1] }
        guard !small.isEmpty, largeTotal > 0 else { return widths }
        let needed = small.reduce(0) { $0 + minimum - widths[$1] }
        for i in widths.indices where widths[i] > 0 {
            widths[i] = small.contains(i) ? minimum : widths[i] - needed * widths[i] / largeTotal
        }
        return widths
    }
}

/// How much room the window gives the dashboard, from its width.
/// - regular (≥ 1100 pt): everything side by side.
/// - compact (860–1100): tighter score text, smaller KPI values.
/// - narrow (< 860): KPI tiles in a 2 × 2 grid; the stage mix moves under the score.
enum LayoutClass: Comparable, Sendable {
    case narrow, compact, regular

    init(width: CGFloat) {
        self = width >= 1100 ? .regular : width >= 860 ? .compact : .narrow
    }
}

private struct LayoutClassKey: EnvironmentKey {
    static let defaultValue = LayoutClass.regular
}

extension EnvironmentValues {
    /// The dashboard's layout class; the header and the page each measure it.
    var layoutClass: LayoutClass {
        get { self[LayoutClassKey.self] }
        set { self[LayoutClassKey.self] = newValue }
    }
}

extension View {
    /// Measures this view's width and puts its `LayoutClass` in the environment below.
    func measuringLayoutClass() -> some View {
        modifier(LayoutClassReader())
    }
}

private struct LayoutClassReader: ViewModifier {
    @State private var layout = LayoutClass.regular

    func body(content: Content) -> some View {
        content
            .environment(\.layoutClass, layout)
            .onGeometryChange(for: LayoutClass.self) { LayoutClass(width: $0.size.width) } action: { layout = $0 }
    }
}
