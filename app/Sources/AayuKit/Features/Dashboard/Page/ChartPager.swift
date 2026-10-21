import SwiftUI

/// One chart at a time, filling the page below the tiles. The ‹ › buttons on
/// the card's edges (or ⌘[ ⌘]) step through them, wrapping round; the dots
/// below show where you are and jump straight to a chart.
struct ChartPager: View {
    let d: Dashboard
    @Environment(DashboardModel.self) private var model

    static let slide = Animation.easeInOut(duration: 0.3)

    var body: some View {
        let pages = ChartPage.available(in: d)
        let page = pages[min(model.chart, pages.count - 1)]
        VStack(spacing: 14) {
            ZStack {
                card(page)
                    .id(page)
                    .transition(.push(from: model.chartForward ? .trailing : .leading))
            }
            .padding(12).clipped().padding(-12)   // clip the slide, not the card's shadow
            .overlay(alignment: .leading) { arrow(forward: false).offset(x: -17) }
            .overlay(alignment: .trailing) { arrow(forward: true).offset(x: 17) }
            dots(pages, current: page)
        }
    }

    @ViewBuilder private func card(_ page: ChartPage) -> some View {
        switch page {
        case .sleep:
            ChartCard(page.title, icon: page.icon) {
                if let night = d.hypnogram { NightStepper(night: night) }
            } content: {
                if let night = d.hypnogram {
                    HypnogramChart(night: night)
                } else {
                    Text("No sleep recorded in this period.").font(.system(size: 13)).foregroundStyle(Theme.sub)
                }
            }
        case .workouts:
            ChartCard(page.title, icon: page.icon) {
                Caption(WorkoutsChart.caption(d.workouts))
            } content: {
                WorkoutsChart(workouts: d.workouts)
            }
        case .calories:
            ChartCard(page.title, icon: page.icon) {
                Caption(CaloriesChart.caption(d.calories))
            } content: {
                CaloriesChart(days: d.calories, window: d.window)
            }
        case .weight:
            if let weight = d.weight {
                ChartCard(page.title, icon: page.icon) {
                    Caption(WeightChart.caption(weight, units: d.units))
                } content: {
                    WeightChart(points: weight, window: d.window, units: d.units)
                }
            }
        }
    }

    private func arrow(forward: Bool) -> some View {
        Button {
            withAnimation(Self.slide) { model.stepChart(forward: forward) }
        } label: {
            Image(systemName: forward ? "chevron.right" : "chevron.left")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 34, height: 34)
                .background(Theme.card, in: Circle())
                .overlay(Circle().strokeBorder(Theme.border))
                .shadow(color: Theme.night.opacity(0.10), radius: 6, y: 2)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(forward ? "Next chart (⌘])" : "Previous chart (⌘[)")
    }

    private func dots(_ pages: [ChartPage], current: ChartPage) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(pages.enumerated()), id: \.element) { i, p in
                Button {
                    withAnimation(Self.slide) { model.showChart(i) }
                } label: {
                    Capsule()
                        .fill(p == current ? Theme.blue : Theme.sub.opacity(0.3))
                        .frame(width: p == current ? 20 : 7, height: 7)
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(p.title)
            }
        }
    }
}
