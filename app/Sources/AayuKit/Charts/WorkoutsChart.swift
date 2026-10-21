import Charts
import SwiftUI

/// Weekly Strength and Running sessions over the two-month axis: a pair of
/// bars per Monday-to-Sunday week, labelled with the week's Monday. Weeks are
/// categories, so each label sits under its own bars, and empty weeks keep their place.
struct WorkoutsChart: View {
    let workouts: Workouts
    @State private var hovered: String?

    /// The key, shown in the card's header.
    static var legend: [ChartLegend.Item] {
        Theme.workoutTypes.map { ChartLegend.Item(name: $0.name, color: $0.color) }
    }

    var body: some View {
        let weeks = Self.visible(workouts)
        let axis = Self.axis(weeks)
        Chart {
            ForEach(weeks) { w in
                BarMark(x: .value("Week", Self.label(w.week)), y: .value("Sessions", w.count), width: .ratio(0.7))
                    .foregroundStyle(by: .value("Type", w.type))
                    .position(by: .value("Type", w.type))
                    .cornerRadius(5)
                    .accessibilityLabel(String(localized: "\(w.type), week of \(w.week.formatted(.dateTime.month(.wide).day()))"))
                    .accessibilityValue(Theme.sessions(w.count))
            }
            if let hovered, let week = weeks.first(where: { Self.label($0.week) == hovered })?.week {
                RuleMark(x: .value("Week", hovered))
                    .foregroundStyle(Theme.hoverRule)
                    .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        HoverCard(title: String(localized: "Week of \(Self.label(week))"),
                                  rows: Theme.workoutTypes.map { type in
                                      let n = weeks.first { $0.week == week && $0.type == type.name }?.count ?? 0
                                      return (type.name, n.formatted(), type.color)
                                  })
                    }
                    .accessibilityHidden(true)
            }
        }
        .chartForegroundStyleScale(domain: Theme.workoutTypes.map(\.name), range: Theme.workoutTypes.map(\.color))
        .chartLegend(.hidden)
        .chartYScale(domain: axis.domain)
        .chartYAxis { valueAxis(step: axis.step) { Theme.sessions(Int($0)) } }
        .chartXScale(domain: Self.weekStarts(workouts).map(Self.label))
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel().font(Theme.micro).foregroundStyle(Theme.sub)
            }
        }
        .chartXSelection(value: $hovered)
    }

    /// A week's category and label: its Monday, "Apr 6".
    static func label(_ week: Date) -> String {
        week.formatted(.dateTime.month(.abbreviated).day())
    }

    /// Weeks that reach into the axis (a week straddling its start included);
    /// weeks entirely before it are off-chart.
    static func visible(_ workouts: Workouts) -> [WorkoutWeek] {
        workouts.weeks.filter { $0.week.addingTimeInterval(7 * 86400) > workouts.start }
    }

    /// Each week the axis covers, by its Monday: from the week holding its start to the one holding its end.
    static func weekStarts(_ workouts: Workouts, calendar: Calendar = Theme.mondayCalendar) -> [Date] {
        Theme.weekStarts(from: workouts.start, through: workouts.end, calendar: calendar)
    }

    /// "12 sessions · last 9 weeks" — sessions across the weeks the axis covers.
    static func caption(_ workouts: Workouts, calendar: Calendar = Theme.mondayCalendar) -> String? {
        let n = total(workouts)
        let weeks = weekStarts(workouts, calendar: calendar).count
        return String(AttributedString(localized: "^[\(n) session](inflect: true) · last ^[\(weeks) week](inflect: true)")
            .characters)
    }

    static func total(_ workouts: Workouts) -> Int {
        visible(workouts).map(\.count).reduce(0, +)
    }

    /// Whole sessions from zero, the top gridline at the busiest week (or a round step above it).
    static func axis(_ weeks: [WorkoutWeek]) -> (domain: ClosedRange<Double>, step: Double) {
        let axis = Theme.niceAxis(0, Double(max(weeks.map(\.count).max() ?? 1, 1)), ticks: 4)
        return (axis.domain, max(1, axis.step.rounded()))
    }
}
