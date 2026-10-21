import Charts
import SwiftUI

/// Weigh-ins across the window.
struct WeightChart: View {
    let points: [WeightPoint]
    let window: DateWindow
    let units: String
    @State private var hovered: Date?

    var body: some View {
        let axis = Self.axis(points)
        Chart {
            ForEach(points) { p in
                AreaMark(x: .value("Date", p.date), yStart: .value(units, axis.domain.lowerBound), yEnd: .value(units, p.value))
                    .foregroundStyle(LinearGradient(colors: [Theme.blue.opacity(0.16), Theme.blue.opacity(0)],
                                                    startPoint: .top, endPoint: .bottom))
                    .accessibilityHidden(true)
            }
            ForEach(points) { p in
                LineMark(x: .value("Date", p.date), y: .value(units, p.value))
                    .foregroundStyle(Theme.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
            ForEach(points.filter(\.marker)) { p in
                PointMark(x: .value("Date", p.date), y: .value(units, p.value))
                    .symbol { Dot(color: Theme.blue) }
                    .accessibilityHidden(true)
            }
            if let p = hoveredPoint {
                RuleMark(x: .value("Date", p.date))
                    .foregroundStyle(Theme.hoverRule)
                    .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        HoverCard(title: p.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()),
                                  rows: [(String(localized: "Weight"), weight(p.value), Theme.blue)])
                    }
                    .accessibilityHidden(true)
                PointMark(x: .value("Date", p.date), y: .value(units, p.value))
                    .symbol { HoverDot(color: Theme.blue) }
                    .accessibilityHidden(true)
            }
        }
        .chartYScale(domain: axis.domain)
        .chartYAxis { valueAxis(step: axis.step) { [units] in "\($0.formatted(.number.precision(.fractionLength(0...1)))) \(units)" } }
        .dayAxis(from: window.start, to: window.end)
        .chartXSelection(value: $hovered)
    }

    /// "−2.8 lbs" — change from the first to the last weigh-in shown.
    static func caption(_ points: [WeightPoint], units: String) -> String? {
        guard let first = points.first, let last = points.last, points.count > 1 else { return nil }
        return String(localized: "\(Theme.signed(last.value - first.value, decimals: 1)) \(units)")
    }

    /// Round steps around the weigh-ins, with half a unit of room either side,
    /// snapped so the top and bottom gridlines are the domain's edges.
    static func axis(_ points: [WeightPoint]) -> (domain: ClosedRange<Double>, step: Double) {
        let values = points.map(\.value)
        return Theme.niceAxis((values.min() ?? 0) - 0.5, (values.max() ?? 1) + 0.5)
    }

    private func weight(_ value: Double) -> String {
        String(localized: "\(value.formatted(.number.precision(.fractionLength(1)))) \(units)")
    }

    /// The weigh-in nearest the pointer.
    private var hoveredPoint: WeightPoint? {
        guard let hovered else { return nil }
        return points.min { abs($0.date.timeIntervalSince(hovered)) < abs($1.date.timeIntervalSince(hovered)) }
    }
}
