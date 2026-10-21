import Charts
import SwiftUI

/// Daily calories with their 7-day average, over the window.
struct CaloriesChart: View {
    let days: [CalorieDay]
    let window: DateWindow
    @State private var hovered: Date?

    /// The key, shown in the card's header.
    static let legend = [ChartLegend.Item(name: String(localized: "Calories"), color: Theme.mist, line: 1.5),
                         ChartLegend.Item(name: String(localized: "7-day avg"), color: Theme.blue, line: 2.5)]

    var body: some View {
        let axis = Self.axis(days)
        Chart {
            ForEach(days) { d in
                AreaMark(x: .value("Day", d.date, unit: .day),
                         yStart: .value("kcal", axis.domain.lowerBound), yEnd: .value("kcal", d.avg7))
                    .foregroundStyle(LinearGradient(colors: [Theme.blue.opacity(0.22), Theme.blue.opacity(0)],
                                                    startPoint: .top, endPoint: .bottom))
                    .accessibilityHidden(true)
            }
            ForEach(days) { d in
                LineMark(x: .value("Day", d.date, unit: .day), y: .value("kcal", d.calories),
                         series: .value("Series", "Calories"))
                    .foregroundStyle(Theme.mist)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
            ForEach(days) { d in
                LineMark(x: .value("Day", d.date, unit: .day), y: .value("kcal", d.avg7),
                         series: .value("Series", "7-day avg"))
                    .foregroundStyle(Theme.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
            if let day = hoveredDay {
                RuleMark(x: .value("Day", day.date, unit: .day))
                    .foregroundStyle(Theme.hoverRule)
                    .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        HoverCard(title: day.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()),
                                  rows: [(String(localized: "Calories"), Self.kcal(day.calories), Theme.mist),
                                         (String(localized: "7-day avg"), Self.kcal(day.avg7), Theme.blue)])
                    }
                    .accessibilityHidden(true)
                PointMark(x: .value("Day", day.date, unit: .day), y: .value("kcal", day.calories))
                    .symbol { HoverDot(color: Theme.mist) }
                    .accessibilityHidden(true)
                PointMark(x: .value("Day", day.date, unit: .day), y: .value("kcal", day.avg7))
                    .symbol { HoverDot(color: Theme.blue) }
                    .accessibilityHidden(true)
            }
        }
        .chartYScale(domain: axis.domain)
        .chartYAxis { valueAxis(step: axis.step) { Self.kcal($0) } }
        .dayAxis(from: window.start, to: window.end)
        .chartXSelection(value: $hovered)
        .chartLegend(.hidden)
    }

    /// "avg 382 kcal" per day in the window.
    static func caption(_ days: [CalorieDay]) -> String? {
        guard !days.isEmpty else { return nil }
        let mean = days.map(\.calories).reduce(0, +) / Double(days.count)
        return String(localized: "avg \(kcal(mean))")
    }

    /// 382.4 → "382 kcal".
    static func kcal(_ value: Double) -> String {
        String(localized: "\(value.formatted(.number.precision(.fractionLength(0)))) kcal")
    }

    /// The value axis: round steps around the lowest and highest values, with a
    /// little room below so the lowest day doesn't sit on the floor. The area
    /// fills down to the floor, not to zero.
    static func axis(_ days: [CalorieDay]) -> (domain: ClosedRange<Double>, step: Double) {
        let values = days.flatMap { [$0.calories, $0.avg7] }
        let lo = values.min() ?? 0, hi = values.max() ?? 100
        let axis = Theme.niceAxis(max(0, lo - (hi - lo) * 0.08), hi)
        return (max(0, axis.domain.lowerBound)...axis.domain.upperBound, axis.step)
    }

    private var hoveredDay: CalorieDay? {
        guard let hovered else { return nil }
        return days.first { Calendar.current.isDate($0.date, inSameDayAs: hovered) }
    }
}
