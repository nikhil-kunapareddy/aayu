import Charts
import SwiftUI

// Axis and marker pieces the dashboard charts share. Charts hover with a rule
// (`Theme.hoverRule`), a point on the hovered value and a `HoverCard` for the
// day (or week) under the pointer. Legends live in the card's header, not in
// the plot, so every plot starts at the same height.

/// Horizontal gridlines with leading labels every `step`; the top label
/// carries the unit ("600 kcal").
@MainActor func valueAxis(step: Double, unit: @escaping (Double) -> String) -> some AxisContent {
    AxisMarks(position: .leading, values: .stride(by: step)) { value in
        AxisGridLine().foregroundStyle(Theme.grid)
        AxisValueLabel {
            if let v = value.as(Double.self) {
                Text(value.index == value.count - 1 ? unit(v) : v.formatted(.number.precision(.fractionLength(0...1))))
            }
        }
        .font(Theme.micro)
        .foregroundStyle(Theme.sub)
    }
}

/// A card-colored dot with a colored ring, for weigh-in markers.
struct Dot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(Theme.card)
            .frame(width: 9, height: 9)
            .overlay(Circle().stroke(color, lineWidth: 2.5))
    }
}

/// The 7-pt point on the hovered value, ringed in the card color so it stands off the line.
struct HoverDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .padding(1.5)
            .background(Theme.card, in: Circle())
    }
}

extension View {
    /// X axis for a run of days: the domain covers start…end (whole days), with
    /// a label and a faint gridline on each Monday. Labels near the ends hang
    /// inward so they aren't cut off at the chart's edges.
    func dayAxis(from start: Date, to end: Date) -> some View {
        let mondays = Theme.mondays(from: start, to: end)
        let last = Theme.dayAfter(end)
        return chartXScale(domain: start...last)
            .chartXAxis {
                AxisMarks(values: mondays) { value in
                    AxisGridLine().foregroundStyle(Theme.grid.opacity(0.7))
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day(), anchor: anchor(value.as(Date.self), start, last))
                        .font(Theme.micro)
                        .foregroundStyle(Theme.sub)
                }
            }
    }
}

/// A day label's anchor: hung inward within two days of either edge.
private func anchor(_ date: Date?, _ start: Date, _ end: Date) -> UnitPoint {
    guard let date else { return .top }
    if date.timeIntervalSince(start) < 2 * 86400 { return .topLeading }
    if end.timeIntervalSince(date) < 2 * 86400 { return .topTrailing }
    return .top
}
