import Charts
import SwiftUI

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
        guard var t = cal.nextDate(after: night.start, matching: DateComponents(minute: 0), matchingPolicy: .nextTime)
        else { return [night.start, night.end] }
        var ticks = [night.start]
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
