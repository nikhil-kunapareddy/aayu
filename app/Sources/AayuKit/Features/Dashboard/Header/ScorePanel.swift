import SwiftUI

/// Score ring and its story, and the window's stage mix: side by side, or
/// (in a narrow window) the stage mix, in a shorter form, under the score's story.
struct ScorePanel: View {
    let d: Dashboard
    @Environment(\.layoutClass) private var layout

    var body: some View {
        Group {
            if layout == .narrow {
                HStack(alignment: .top, spacing: 24) {
                    ring
                    VStack(alignment: .leading, spacing: 16) {
                        story
                        StageMix(stages: d.stages, range: d.selection, inline: true)
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 28) {
                    ring
                    story.frame(maxWidth: layout == .regular ? 330 : 260, alignment: .leading)
                    Rectangle().fill(Theme.panelStroke).frame(width: 1)
                    StageMix(stages: d.stages, range: d.selection)
                }
                .fixedSize(horizontal: false, vertical: true)   // as tall as its content; the divider follows
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frosted(RoundedRectangle(cornerRadius: Theme.panelRadius))
    }

    private var ring: some View {
        ScoreRing(score: d.kpis.sleepScore)
            .frame(width: layout == .narrow ? 112 : 124, height: layout == .narrow ? 112 : 124)
            .help(String(localized: """
                Your sleep score for the 14 nights up to \(d.window.end.formatted(.dateTime.month(.wide).day())), \
                from bed and wake timing, schedule consistency, sleep stages and time asleep.
                """))
    }

    /// "Sleep Score", the change pill, and what the score's parts say.
    private var story: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sleep Score")
                .font(Theme.title2)
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            if let change = d.kpis.sleepScoreChange {
                ScorePill(change: ChangeLabel(Double(change), higherIsBetter: true, surface: .header) {
                    String(localized: "\($0) vs the 14 nights before")
                })
            }
            Text(ScoreText.message(d.kpis.sleepScore, d.kpis.sleepScoreParts))
                .font(Theme.body)
                .foregroundStyle(.white.opacity(0.75))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }
}

/// The score's change in a tinted capsule.
struct ScorePill: View {
    let change: ChangeLabel

    var body: some View {
        change
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(tint, in: Capsule())
    }

    private var tint: Color {
        switch change.tone {
        case .better: Theme.upOnDark.opacity(0.16)
        case .worse: Theme.downOnDark.opacity(0.16)
        case .neutral: .white.opacity(0.08)
        }
    }
}

/// The score as a gradient ring out of 100; the ring fills when the score arrives or changes.
struct ScoreRing: View {
    let score: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0.0

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.10), lineWidth: 12)
            Circle()
                .trim(from: 0, to: shown / 100)
                .stroke(Theme.ring, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(score.map { $0.formatted() } ?? "—")
                    .font(Theme.score)
                    .contentTransition(.numericText(value: Double(score ?? 0)))
                    .animation(reduceMotion ? nil : .smooth, value: score)
                Text("/100").font(Theme.bodyEmphasis).opacity(0.6)
            }
            .foregroundStyle(.white)
        }
        .padding(6)   // half the stroke, which straddles the circle's edge
        .onChange(of: score, initial: true) { _, score in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.6)) { shown = Double(score ?? 0) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sleep score")
        .accessibilityValue(score.map { String(localized: "\($0) out of 100") } ?? String(localized: "No score"))
    }
}

/// "Sleep Stages": a bar of the window's stage shares and a legend, both in
/// the hypnogram's order (Awake, REM, Light, Deep), as whole percentages.
/// `inline` is the short form for a narrow window: no title, and each share
/// beside its name.
struct StageMix: View {
    let stages: [StageShare]
    let range: String
    var inline = false

    private static let spacing: CGFloat = 2
    private static let minimum: CGFloat = 3

    var body: some View {
        let order = Theme.stagesByDepth
        let shares = order.map { stage in stages.first { $0.stage == stage.name }?.share ?? 0 }
        let percents = Theme.wholePercents(shares)
        VStack(alignment: .leading, spacing: 12) {
            if !inline {
                Text("Sleep Stages")
                    .font(Theme.title2)
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
            }
            bar(shares: shares, colors: order.map(\.color))
                .frame(height: inline ? 8 : 12)
                .accessibilityHidden(true)
            Grid(alignment: .leading, horizontalSpacing: 16) {
                GridRow {
                    ForEach(order.indices, id: \.self) { i in
                        item(order[i].name, color: order[i].color, percent: percents[i])
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .padding(.top, inline ? 0 : 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sleep stages")
        .help(String(localized: "How your nights split between the sleep stages across \(Theme.rangePhrase(range))."))
    }

    @ViewBuilder private func item(_ name: String, color: Color, percent: Int) -> some View {
        let label = HStack(spacing: 8) {
            Swatch(color: color)
            Text(name).font(Theme.bodyEmphasis).foregroundStyle(.white.opacity(0.85))
        }
        let value = Text(Theme.percent(whole: percent)).foregroundStyle(.white).monospacedDigit()
        if inline {
            HStack(spacing: 8) { label; value.font(Theme.bodyEmphasis.weight(.semibold)) }
        } else {
            VStack(alignment: .leading, spacing: 4) { label; value.font(Theme.title2) }
        }
    }

    private func bar(shares: [Double], colors: [Color]) -> some View {
        GeometryReader { geo in
            let widths = Theme.segmentWidths(shares, total: geo.size.width, spacing: Self.spacing, minimum: Self.minimum)
            HStack(spacing: Self.spacing) {
                ForEach(widths.indices, id: \.self) { i in
                    if widths[i] > 0 { Rectangle().fill(colors[i]).frame(width: widths[i]) }
                }
            }
            .frame(width: geo.size.width, alignment: .leading)
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
}
