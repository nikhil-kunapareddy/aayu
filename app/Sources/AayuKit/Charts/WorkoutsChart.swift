import Charts
import SwiftUI

/// Weekly Strength and Running sessions over the two-month axis.
struct WorkoutsChart: View {
    let workouts: Workouts
    @State private var hovered: Date?

    var body: some View {
        let weeks = Self.visible(workouts)
        Chart {
            ForEach(weeks) { w in
                BarMark(x: .value("Week", w.week, unit: .weekOfYear), y: .value("Sessions", w.count), width: .ratio(0.7))
                    .foregroundStyle(by: .value("Type", w.type))
                    .position(by: .value("Type", w.type))
                    .cornerRadius(5)
            }
            if let week = hoveredWeek(in: weeks) {
                RuleMark(x: .value("Week", week, unit: .weekOfYear))
                    .foregroundStyle(Theme.grid)
                    .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        HoverCard(title: "Week of " + week.formatted(.dateTime.month(.abbreviated).day()),
                                  rows: Theme.workoutTypes.map { type in
                                      let n = weeks.first { $0.week == week && $0.type == type.name }?.count ?? 0
                                      return (type.name, "\(n)", type.color)
                                  })
                    }
            }
        }
        .chartForegroundStyleScale(domain: Theme.workoutTypes.map(\.name), range: Theme.workoutTypes.map(\.color))
        .chartYAxis {
            AxisMarks(position: .leading, values: .stride(by: 1)) { _ in
                AxisGridLine().foregroundStyle(Theme.grid)
                AxisValueLabel().font(.system(size: 10)).foregroundStyle(Theme.sub)
            }
        }
        .dayAxis(from: workouts.start, to: workouts.end, everyDays: 14, domainStart: weeks.map(\.week).min())
        .chartXSelection(value: $hovered)
        .chartLegend(position: .top, alignment: .trailing)
        .environment(\.calendar, Theme.mondayCalendar)
    }

    /// Weeks that reach into the axis. A week straddling its start widens the
    /// domain a few days so the whole bar shows; weeks entirely before it are off-chart.
    static func visible(_ workouts: Workouts) -> [WorkoutWeek] {
        workouts.weeks.filter { $0.week.addingTimeInterval(7 * 86400) > workouts.start }
    }

    /// "12 sessions" across the weeks shown.
    static func caption(_ workouts: Workouts) -> String? {
        let n = visible(workouts).map(\.count).reduce(0, +)
        return n == 1 ? "1 session" : "\(n) sessions"
    }

    private func hoveredWeek(in weeks: [WorkoutWeek]) -> Date? {
        guard let hovered else { return nil }
        return weeks.first { $0.week <= hovered && hovered < $0.week.addingTimeInterval(7 * 86400) }?.week
    }
}
