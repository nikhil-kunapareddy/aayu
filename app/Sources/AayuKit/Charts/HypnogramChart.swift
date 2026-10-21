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
            // Side by side when they fit; otherwise the breakdown goes under the summary.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) {
                    summary
                    Spacer(minLength: 0)
                    breakdown(spacing: 32)
                }
                VStack(alignment: .leading, spacing: 12) {
                    summary
                    breakdown(spacing: 24)
                }
            }
            if night.segments.isEmpty {
                EmptyChart(title: String(localized: "No Stage Data"), icon: "moon.zzz",
                           message: String(localized: "The watch didn't record sleep stages for this night."))
            } else {
                chart
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
                    .accessibilityChartDescriptor(HypnogramDescriptor(night: night))
            }
        }
    }

    /// "7h 36m" (as `Theme.duration` writes it) over "asleep · 7h 52m total".
    private var summary: some View {
        let number = { (n: Int) in Text(n.formatted()).font(Theme.metric).foregroundStyle(Theme.ink) }
        let unit = { (u: String) in Text(u).font(Theme.title3.weight(.medium)).foregroundStyle(Theme.sub) }
        let hours = night.asleep / 60, minutes = night.asleep % 60
        return VStack(alignment: .leading, spacing: 2) {
            Group {
                if hours > 0 {
                    Text("\(number(hours))\(unit("h")) \(number(minutes))\(unit("m"))")
                } else {
                    Text("\(number(minutes))\(unit("m"))")
                }
            }
            .accessibilityLabel(String(localized: "\(Theme.spokenDuration(minutes: night.asleep)) asleep"))
            Text("asleep · \(Theme.duration(minutes: night.duration)) total")
                .font(Theme.caption)
                .foregroundStyle(Theme.sub)
                .accessibilityLabel(String(localized: "\(Theme.spokenDuration(minutes: night.duration)) in bed"))
        }
        .accessibilityElement(children: .combine)
    }

    /// Each stage's time and share, in the chart's top-to-bottom order, with a
    /// bar scaled to the largest share. Shares are whole percentages that sum to 100.
    private func breakdown(spacing: CGFloat) -> some View {
        let stages = Theme.stagesByDepth
        let totals = stages.map { stage in night.totals.first { $0.stage == stage.name } }
        let percents = Theme.wholePercents(totals.map { $0?.share ?? 0 })
        let longest = max(totals.map { $0?.share ?? 0 }.max() ?? 0, 0.01)
        return HStack(alignment: .top, spacing: spacing) {
            ForEach(stages.indices, id: \.self) { i in
                let t = totals[i]
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Text(stages[i].name).fontWeight(.semibold)
                        Text(Theme.duration(minutes: t?.minutes ?? 0))
                    }
                    .foregroundStyle(Theme.ink)
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(stages[i].color)
                            .frame(width: max(4, 64 * (t?.share ?? 0) / longest), height: 10)
                        Text(Theme.percent(whole: percents[i])).foregroundStyle(Theme.sub)
                    }
                }
                .fixedSize()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(stages[i].name)
                .accessibilityValue(String(localized:
                    "\(Theme.spokenDuration(minutes: t?.minutes ?? 0)), \(Theme.percent(whole: percents[i]))"))
            }
        }
        .font(Theme.caption)
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
                    .accessibilityHidden(true)
            }
            ForEach(night.segments) { s in
                let level = Theme.stageLevel(s.stage)
                RectangleMark(xStart: .value("From", s.start), xEnd: .value("To", s.end),
                              yStart: .value("Level", level - Self.band), yEnd: .value("Level", level + Self.band))
                    .foregroundStyle(Theme.stageColor(s.stage))
                    .cornerRadius(3)
                    .accessibilityLabel(s.stage)
                    .accessibilityValue(s.spoken)
            }
            // Bedtime and wake time, over a baseline.
            RuleMark(x: .value("At", night.start)).foregroundStyle(Theme.sub.opacity(0.35)).accessibilityHidden(true)
            RuleMark(x: .value("At", night.end)).foregroundStyle(Theme.sub.opacity(0.35)).accessibilityHidden(true)
            RuleMark(y: .value("Level", Self.floor)).foregroundStyle(Theme.sub.opacity(0.35)).accessibilityHidden(true)
            if let s = hoveredSpan, let at = hovered {
                RuleMark(x: .value("At", at))
                    .foregroundStyle(Theme.hoverRule)
                    .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        HoverCard(title: s.stage, rows: [(
                            (s.start..<s.end).formatted(.interval.hour().minute()),
                            Theme.duration(minutes: s.minutes),
                            Theme.stageColor(s.stage))])
                    }
                    .accessibilityHidden(true)
                PointMark(x: .value("At", at), y: .value("Level", Theme.stageLevel(s.stage)))
                    .symbol { HoverDot(color: Theme.stageColor(s.stage)) }
                    .accessibilityHidden(true)
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
                                .font(Theme.micro.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.page, in: .rect(cornerRadius: 4))
                        }
                    }
                } else {
                    AxisValueLabel(format: .dateTime.hour(), anchor: .top)
                        .font(Theme.micro.weight(.medium))
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

/// The hypnogram for VoiceOver's chart navigation and Audio Graphs: time since
/// bedtime across, stage depth up (Deep 0 … Awake 3), one point per stage run.
struct HypnogramDescriptor: AXChartDescriptorRepresentable {
    let night: Hypnogram

    func makeChartDescriptor() -> AXChartDescriptor {
        let start = night.start
        let span = max(night.end.timeIntervalSince(start) / 60, 1)
        let names = Dictionary(uniqueKeysWithValues: Theme.stages.map { ($0.level, $0.name) })
        let time = AXNumericDataAxisDescriptor(title: String(localized: "Time"), range: 0...span, gridlinePositions: []) {
            start.addingTimeInterval($0 * 60).formatted(date: .omitted, time: .shortened)
        }
        let stage = AXNumericDataAxisDescriptor(title: String(localized: "Stage"), range: 0...3, gridlinePositions: [0, 1, 2, 3]) {
            names[$0.rounded()] ?? ""
        }
        let points = night.segments.map { s in
            AXDataPoint(x: s.start.timeIntervalSince(start) / 60, y: Theme.stageLevel(s.stage),
                        label: "\(s.stage), \(s.spoken)")
        }
        let summary = String(localized: """
            \(Theme.spokenDuration(minutes: night.asleep)) asleep, from \(start.formatted(date: .omitted, time: .shortened)) \
            to \(night.end.formatted(date: .omitted, time: .shortened)).
            """)
        return AXChartDescriptor(title: String(localized: "Sleep Breakdown"), summary: summary, xAxis: time, yAxis: stage,
                                 additionalAxes: [],
                                 series: [AXDataSeriesDescriptor(name: String(localized: "Stages"), isContinuous: false,
                                                                 dataPoints: points)])
    }

    func updateChartDescriptor(_ descriptor: AXChartDescriptor) {}
}

extension StageSpan {
    /// Its length in whole minutes.
    var minutes: Int { Int((end.timeIntervalSince(start) / 60).rounded()) }

    /// "1:12 – 2:03 AM, 51 minutes" — a band, for VoiceOver.
    var spoken: String {
        String(localized: "\((start..<end).formatted(.interval.hour().minute())), \(Theme.spokenDuration(minutes: minutes))")
    }
}
