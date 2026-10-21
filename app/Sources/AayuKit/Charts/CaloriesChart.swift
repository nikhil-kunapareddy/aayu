import Charts
import SwiftUI

/// Daily calories with their 7-day average, over the window.
struct CaloriesChart: View {
    let days: [CalorieDay]
    let window: DateWindow
    @State private var hovered: Date?

    var body: some View {
        let floor = valueFloor
        Chart {
            ForEach(days) { d in
                AreaMark(x: .value("Day", d.date, unit: .day), yStart: .value("kcal", floor), yEnd: .value("kcal", d.avg7))
                    .foregroundStyle(LinearGradient(colors: [Theme.blue.opacity(0.22), Theme.blue.opacity(0)],
                                                    startPoint: .top, endPoint: .bottom))
            }
            ForEach(days) { d in
                LineMark(x: .value("Day", d.date, unit: .day), y: .value("kcal", d.calories),
                         series: .value("Series", "Calories"))
                    .foregroundStyle(by: .value("Series", "Calories"))
                    .lineStyle(StrokeStyle(lineWidth: 1.2))
            }
            ForEach(days) { d in
                LineMark(x: .value("Day", d.date, unit: .day), y: .value("kcal", d.avg7),
                         series: .value("Series", "7-day avg"))
                    .foregroundStyle(by: .value("Series", "7-day avg"))
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
            ForEach(days.filter(\.marker)) { d in
                PointMark(x: .value("Day", d.date, unit: .day), y: .value("kcal", d.avg7))
                    .symbol { Dot(color: Theme.blue) }
            }
            if let day = hoveredDay {
                RuleMark(x: .value("Day", day.date, unit: .day))
                    .foregroundStyle(Theme.grid)
                    .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        HoverCard(title: day.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()),
                                  rows: [("Calories", "\(Int(day.calories)) kcal", Theme.mist),
                                         ("7-day avg", "\(Int(day.avg7)) kcal", Theme.blue)])
                    }
            }
        }
        .chartForegroundStyleScale(["Calories": Theme.mist, "7-day avg": Theme.blue])
        .chartYScale(domain: floor...valueCeiling)
        .chartYAxis { gridAxis }
        .dayAxis(from: window.start, to: window.end)
        .chartXSelection(value: $hovered)
        .chartLegend(position: .top, alignment: .trailing)
    }

    /// "avg 382 kcal" per day in the window.
    static func caption(_ days: [CalorieDay]) -> String? {
        guard !days.isEmpty else { return nil }
        return "avg \(Int((days.map(\.calories).reduce(0, +) / Double(days.count)).rounded())) kcal"
    }

    // The area fills down to a round number under the lowest value, not to zero.
    private var valueFloor: Double {
        let lo = days.flatMap { [$0.calories, $0.avg7] }.min() ?? 0
        return max(0, (lo / 100).rounded(.down) * 100)
    }

    private var valueCeiling: Double {
        let hi = days.flatMap { [$0.calories, $0.avg7] }.max() ?? 100
        return max(valueFloor + 100, (hi / 100).rounded(.up) * 100)
    }

    private var hoveredDay: CalorieDay? {
        guard let hovered else { return nil }
        return days.first { Calendar.current.isDate($0.date, inSameDayAs: hovered) }
    }
}
