import SwiftUI

/// Score ring and its story on the left, the window's stage mix on the right.
struct ScorePanel: View {
    let d: Dashboard

    var body: some View {
        HStack(spacing: 28) {
            ScoreRing(score: d.kpis.sleepScore)
                .frame(width: 124, height: 124)
            VStack(alignment: .leading, spacing: 10) {
                Text("Sleep Score")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                if let change = d.kpis.sleepScoreChange {
                    Label("\(Theme.signed(Double(change))) vs the 14 nights before",
                          systemImage: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(change >= 0 ? Theme.upOnDark : Theme.stageColor("Awake"))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background((change >= 0 ? Theme.up : Theme.down).opacity(0.22), in: Capsule())
                }
                Text(ScoreText.message(d.kpis.sleepScore, d.kpis.sleepScoreParts))
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 330, alignment: .leading)
            Rectangle().fill(Theme.panelStroke).frame(width: 1).padding(.vertical, 4)
            StageMix(stages: d.stages)
        }
        .fixedSize(horizontal: false, vertical: true)   // as tall as its content; the divider follows
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frosted(RoundedRectangle(cornerRadius: Theme.panelRadius))
    }
}

/// The score as a gradient ring out of 100.
struct ScoreRing: View {
    let score: Int?

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.10), lineWidth: 12)
            Circle()
                .trim(from: 0, to: Double(score ?? 0) / 100)
                .stroke(Theme.ring, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(score.map(String.init) ?? "—").font(.system(size: 42, weight: .semibold))
                Text("/100").font(.system(size: 13, weight: .medium)).opacity(0.6)
            }
            .foregroundStyle(.white)
            .monospacedDigit()
        }
        .padding(6)
    }
}

/// "Sleep Stages": a stacked bar of the window's stage shares and a legend.
struct StageMix: View {
    let stages: [StageShare]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 24) {
                Text("Sleep Stages")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                bar.frame(maxWidth: 280).frame(height: 14)
            }
            Grid(alignment: .leading, horizontalSpacing: 40, verticalSpacing: 12) {
                GridRow { item("Deep"); item("Light") }
                GridRow { item("REM"); item("Awake") }
            }
        }
        .frame(maxWidth: .infinity)
        .environment(\.colorScheme, .dark)   // the header is dark in both appearances
    }

    private func share(_ name: String) -> Double {
        stages.first { $0.stage == name }?.share ?? 0
    }

    private var bar: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(Theme.stages, id: \.name) { stage in
                    Rectangle()
                        .fill(stage.color)
                        .frame(width: max(0, geo.size.width - 6) * share(stage.name))
                }
            }
            .clipShape(Capsule())
        }
    }

    private func item(_ name: String) -> some View {
        HStack(spacing: 10) {
            Swatch(color: Theme.stageColor(name), size: 12)
            Text(name).font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.85))
            Spacer(minLength: 24)
            Text(Theme.percent(share(name)))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .frame(width: 170)
    }
}
