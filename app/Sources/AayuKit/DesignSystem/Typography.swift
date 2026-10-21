import SwiftUI

// The type scale. Every text style in the app comes from here; vary weight
// with `.weight(_:)` rather than adding sizes. Numbers that change in place
// (scores, KPI values) use rounded, monospaced digits so they don't jiggle.
extension Theme {
    /// 34 semibold — the largest headline (welcome screens).
    static let display = Font.system(size: 34, weight: .semibold)
    /// 42 semibold rounded — the sleep score in its ring.
    static let score = Font.system(size: 42, weight: .semibold, design: .rounded).monospacedDigit()
    /// 26 semibold — the greeting.
    static let largeTitle = Font.system(size: 26, weight: .semibold)
    /// 28 semibold rounded — KPI values, the night's time asleep.
    static let metric = Font.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit()
    /// 26 semibold rounded — KPI values when the window is a little narrow.
    static let metricCompact = Font.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit()
    /// 17 semibold — section titles on the header ("Sleep Score", stage shares).
    static let title2 = Font.system(size: 17, weight: .semibold)
    /// 15 semibold — card titles.
    static let title3 = Font.system(size: 15, weight: .semibold)
    /// 13 — running text.
    static let body = Font.system(size: 13)
    /// 13 medium — tile titles, legend names.
    static let bodyEmphasis = Font.system(size: 13, weight: .medium)
    /// 12 — captions, changes, secondary lines.
    static let caption = Font.system(size: 12)
    /// 11 — chart axes, time chips, tooltips.
    static let micro = Font.system(size: 11)
}
