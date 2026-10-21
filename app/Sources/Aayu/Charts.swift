import Charts
import SwiftUI

// One view per dashboard chart, drawn with Swift Charts from the backend's
// series, plus the one-line caption a card shows beside its title.
// Hovering shows a rule and a tooltip for the day (or week) under the pointer.
// Shared axis and tooltip pieces are at the bottom.

/// One night as a hypnogram: a thick band per stage run at its level (Awake on
/// top, Deep at the bottom), joined by a thin gradient riser where the stage
/// changes, between bedtime and wake time. Above it, the time asleep and each
/// stage's time, with a bar for its share of the night.
struct HypnogramChart: View {
    let night: Hypnogram
    @State private var hovered: Date?
    @State private var width: CGFloat = 0

    /// Half a band's height, in levels (bands are a level apart).
    private static let band = 0.39

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 24) {
                summary
                Spacer(minLength: 0)
                breakdown
            }
            if night.segments.isEmpty {
                Text("No stage data for this night.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.sub)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                chart.onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            }
        }
    }

    /// "6 h 23 min" over "asleep · 7h 29m total".
    private var summary: some View {
        let number = { (n: Int) in Text("\(n)").font(.system(size: 30, weight: .semibold)).foregroundStyle(Theme.ink) }
        let unit = { (u: String) in Text(u).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.sub) }
        return VStack(alignment: .leading, spacing: 1) {
            Text("\(number(night.asleep / 60))\(unit(" h "))\(number(night.asleep % 60))\(unit(" min"))")
            Text("asleep · " + Theme.duration(minutes: night.duration) + " total")
                .font(.system(size: 12))
                .foregroundStyle(Theme.sub)
        }
        .monospacedDigit()
    }

    /// Each stage's time and share, in the chart's top-to-bottom order, with a
    /// bar scaled to the largest share.
    private var breakdown: some View {
        let longest = max(night.totals.map(\.share).max() ?? 0, 0.01)
        return HStack(alignment: .top, spacing: 32) {
            ForEach(Theme.stages.sorted { $0.level > $1.level }, id: \.name) { stage in
                let t = night.totals.first { $0.stage == stage.name }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Text(stage.name).fontWeight(.semibold)
                        Text(Theme.duration(minutes: t?.minutes ?? 0))
                    }
                    .foregroundStyle(Theme.ink)
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(stage.color)
                            .frame(width: max(4, 64 * (t?.share ?? 0) / longest), height: 10)
                        Text(Theme.percent(t?.share ?? 0)).foregroundStyle(Theme.sub)
                    }
                }
            }
        }
        .font(.system(size: 12))
        .monospacedDigit()
    }

    private var chart: some View {
        Chart {
            // Risers first, so the bands cover their ends. Each runs from just
            // inside one band to just inside the next, fading between their colors.
            ForEach(joins, id: \.at) { j in
                let dir = j.to > j.from ? 1.0 : -1.0
                RectangleMark(x: .value("At", j.at),
                              yStart: .value("Level", j.from + dir * (Self.band - 0.05)),
                              yEnd: .value("Level", j.to - dir * (Self.band - 0.05)), width: 3)
                    .foregroundStyle(LinearGradient(colors: [Theme.stageColor(j.fromStage), Theme.stageColor(j.toStage)],
                                                    startPoint: dir > 0 ? .bottom : .top,
                                                    endPoint: dir > 0 ? .top : .bottom))
            }
            ForEach(night.segments) { s in
                let level = Theme.stageLevel(s.stage)
                RectangleMark(xStart: .value("From", s.start), xEnd: .value("To", s.end),
                              yStart: .value("Level", level - Self.band), yEnd: .value("Level", level + Self.band))
                    .foregroundStyle(Theme.stageColor(s.stage))
                    .cornerRadius(3)
            }
            // Bedtime and wake time, over a baseline.
            RuleMark(x: .value("At", night.start)).foregroundStyle(Theme.sub.opacity(0.35))
            RuleMark(x: .value("At", night.end)).foregroundStyle(Theme.sub.opacity(0.35))
            RuleMark(y: .value("Level", Self.floor)).foregroundStyle(Theme.sub.opacity(0.35))
            if let s = hoveredSpan {
                RuleMark(x: .value("At", hovered ?? s.start))
                    .foregroundStyle(Theme.sub.opacity(0.5))
                    .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        HoverCard(title: s.stage, rows: [(
                            s.start.formatted(date: .omitted, time: .shortened) + " – "
                                + s.end.formatted(date: .omitted, time: .shortened),
                            Theme.duration(minutes: Int(s.end.timeIntervalSince(s.start) / 60)),
                            Theme.stageColor(s.stage))])
                    }
            }
        }
        .chartYScale(domain: Self.floor...3.42)
        .chartYAxis(.hidden)
        .chartXScale(domain: domain)
        .chartXAxis {
            AxisMarks(values: timeTicks) { value in
                let first = value.index == 0, last = value.index == value.count - 1
                if first || last {
                    // Bedtime and wake time in chips, hanging inward from their rules.
                    AxisValueLabel(anchor: first ? .topLeading : .topTrailing) {
                        if let date = value.as(Date.self) {
                            Text(date, format: .dateTime.hour().minute())
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Theme.page, in: .rect(cornerRadius: 4))
                        }
                    }
                } else {
                    AxisValueLabel(format: .dateTime.hour(), anchor: .top)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.sub)
                }
            }
        }
        .chartXSelection(value: $hovered)
    }

    /// The baseline's level, a little below the Deep band.
    private static let floor = -0.6

    /// Bedtime to wake time, with a sliver either side so the edge rules and
    /// band corners aren't clipped.
    private var domain: ClosedRange<Date> {
        let pad = night.end.timeIntervalSince(night.start) * 0.006
        return night.start.addingTimeInterval(-pad)...night.end.addingTimeInterval(pad)
    }

    private struct Join {
        let at: Date
        let from: Double, to: Double
        let fromStage: String, toStage: String
    }

    /// Stage changes between back-to-back segments.
    private var joins: [Join] {
        zip(night.segments, night.segments.dropFirst()).compactMap { a, b in
            guard a.end == b.start, a.stage != b.stage else { return nil }
            return Join(at: a.end, from: Theme.stageLevel(a.stage), to: Theme.stageLevel(b.stage),
                        fromStage: a.stage, toStage: b.stage)
        }
    }

    /// Bedtime, every second whole hour clear of the end chips, wake time.
    private var timeTicks: [Date] {
        let cal = Calendar.current
        let span = night.end.timeIntervalSince(night.start)
        let clear = width > 0 ? span * 78 / width : 5400   // a chip and half an hour label, in seconds
        var ticks = [night.start]
        var t = cal.nextDate(after: night.start, matching: DateComponents(minute: 0), matchingPolicy: .nextTime)!
        while t < night.end {
            let hour = cal.component(.hour, from: t)
            if hour % 2 == 0, t.timeIntervalSince(night.start) > clear, night.end.timeIntervalSince(t) > clear {
                ticks.append(t)
            }
            t = t.addingTimeInterval(3600)
        }
        ticks.append(night.end)
        return ticks
    }

    private var hoveredSpan: StageSpan? {
        guard let hovered else { return nil }
        return night.segments.first { $0.start <= hovered && hovered < $0.end }
    }
}

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

// ── Shared pieces ─────────────────────────────────────────────────────────────

/// Horizontal gridlines with leading labels.
private var gridAxis: some AxisContent {
    AxisMarks(position: .leading) { _ in
        AxisGridLine().foregroundStyle(Theme.grid)
        AxisValueLabel().font(.system(size: 10)).foregroundStyle(Theme.sub)
    }
}

/// A card-colored dot with a colored ring, for line markers.
private struct Dot: View {
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

/// The tooltip shown above the hovered day: a title and colored value rows.
struct HoverCard: View {
    let title: String
    let rows: [(String, String, Color)]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).fontWeight(.semibold).foregroundStyle(Theme.ink)
            ForEach(rows.indices, id: \.self) { i in
                HStack(spacing: 6) {
                    Circle().fill(rows[i].2).frame(width: 7, height: 7)
                    Text(rows[i].0).foregroundStyle(Theme.sub)
                    Spacer(minLength: 12)
                    Text(rows[i].1).foregroundStyle(Theme.ink).monospacedDigit()
                }
            }
        }
        .font(.system(size: 11))
        .padding(10)
        .frame(minWidth: 150)
        .background(Theme.card, in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
        .shadow(color: Theme.night.opacity(0.12), radius: 12, y: 4)
    }
}
