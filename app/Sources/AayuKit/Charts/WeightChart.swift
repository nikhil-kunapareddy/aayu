import Charts
import SwiftUI

/// Weigh-ins across the window.
struct WeightChart: View {
    let points: [WeightPoint]
    let window: DateWindow
    let units: String
    @State private var hovered: Date?

    var body: some View {
        let floor = valueFloor
        Chart {
            ForEach(points) { p in
                AreaMark(x: .value("Date", p.date), yStart: .value(units, floor), yEnd: .value(units, p.value))
                    .foregroundStyle(LinearGradient(colors: [Theme.blue.opacity(0.16), Theme.blue.opacity(0)],
                                                    startPoint: .top, endPoint: .bottom))
            }
            ForEach(points) { p in
                LineMark(x: .value("Date", p.date), y: .value(units, p.value))
                    .foregroundStyle(Theme.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
            ForEach(points.filter(\.marker)) { p in
                PointMark(x: .value("Date", p.date), y: .value(units, p.value))
                    .symbol { Dot(color: Theme.blue) }
            }
            if let p = hoveredPoint {
                RuleMark(x: .value("Date", p.date))
                    .foregroundStyle(Theme.grid)
                    .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        HoverCard(title: p.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()),
                                  rows: [("Weight", p.value.formatted(.number.precision(.fractionLength(1))) + " " + units,
                                          Theme.blue)])
                    }
            }
        }
        .chartYScale(domain: floor...valueCeiling)
        .chartYAxis { gridAxis }
        .dayAxis(from: window.start, to: window.end)
        .chartXSelection(value: $hovered)
    }

    /// "−2.8 lbs" — change from the first to the last weigh-in shown.
    static func caption(_ points: [WeightPoint], units: String) -> String? {
        guard let first = points.first, let last = points.last, points.count > 1 else { return nil }
        let change = last.value - first.value
        return change.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always(includingZero: false)))
            + " " + units
    }

    private var valueFloor: Double {
        ((points.map(\.value).min() ?? 0) - 1).rounded(.down)
    }

    private var valueCeiling: Double {
        ((points.map(\.value).max() ?? 1) + 1).rounded(.up)
    }

    /// The weigh-in nearest the pointer.
    private var hoveredPoint: WeightPoint? {
        guard let hovered else { return nil }
        return points.min { abs($0.date.timeIntervalSince(hovered)) < abs($1.date.timeIntervalSince(hovered)) }
    }
}
