import Charts
import SwiftUI

// Axis and marker pieces the dashboard charts share. Charts hover with a
// rule and a `HoverCard` for the day (or week) under the pointer.

/// Horizontal gridlines with leading labels.
@MainActor var gridAxis: some AxisContent {
    AxisMarks(position: .leading) { _ in
        AxisGridLine().foregroundStyle(Theme.grid)
        AxisValueLabel().font(.system(size: 10)).foregroundStyle(Theme.sub)
    }
}

/// A card-colored dot with a colored ring, for line markers.
struct Dot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(Theme.card)
            .frame(width: 9, height: 9)
            .overlay(Circle().stroke(color, lineWidth: 2.5))
    }
}

extension View {
    /// X axis for a run of days: the domain covers start…end (whole days), with
    /// labels on the first and last day and every `everyDays` between. The end
    /// labels hang inward so they aren't cut off at the chart's edges.
    /// `domainStart` widens the domain leftward without moving the labels.
    func dayAxis(from start: Date, to end: Date, everyDays: Int = 7, domainStart: Date? = nil) -> some View {
        let ticks = Theme.dayTicks(from: start, to: end, everyDays: everyDays)
        return chartXScale(domain: min(start, domainStart ?? start)...Theme.dayAfter(end))
            .chartXAxis {
                AxisMarks(values: ticks) { value in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day(),
                                   anchor: value.index == 0 ? .topLeading
                                       : value.index == value.count - 1 ? .topTrailing : .top)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.sub)
                }
            }
    }
}
