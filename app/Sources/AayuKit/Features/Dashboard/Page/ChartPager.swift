import AppKit
import SwiftUI

/// One chart at a time, filling the page below the tiles. The ‹ › buttons on
/// the card's edges (or ⌘[ ⌘]) step through them, wrapping round; the dots
/// below show where you are and jump straight to a chart.
struct ChartPager: View {
    let d: Dashboard
    @Environment(DashboardModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The page change: a slide, or with Reduce Motion a short cross-fade.
    static var slide: Animation {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.35)
    }

    var body: some View {
        let pages = ChartPage.available(in: d)
        let page = pages[min(model.chart, pages.count - 1)]
        VStack(spacing: 8) {
            ZStack {
                card(page)
                    .id(page)
                    .transition(reduceMotion ? .opacity : .push(from: model.chartForward ? .trailing : .leading))
            }
            .frame(minHeight: Theme.chartMinHeight, maxHeight: .infinity)
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
                    EmptyChart(title: String(localized: "No Sleep Recorded"), icon: "moon.zzz",
                               message: String(localized: "There’s no sleep data for \(range)."))
                }
            }
        case .workouts:
            let empty = WorkoutsChart.total(d.workouts) == 0
            ChartCard(page.title, icon: page.icon, caption: empty ? nil : WorkoutsChart.caption(d.workouts)) {
                if !empty { ChartLegend(items: WorkoutsChart.legend) }
            } content: {
                if empty {
                    EmptyChart(title: String(localized: "No Workouts"), icon: "figure.run",
                               message: String(localized: "No Strength or Running sessions in the weeks up to \(end)."))
                } else {
                    WorkoutsChart(workouts: d.workouts)
                }
            }
        case .calories:
            ChartCard(page.title, icon: page.icon, caption: CaloriesChart.caption(d.calories)) {
                if !d.calories.isEmpty { ChartLegend(items: CaloriesChart.legend) }
            } content: {
                if d.calories.isEmpty {
                    EmptyChart(title: String(localized: "No Activity Data"), icon: "flame",
                               message: String(localized: "There’s no calorie data for \(range)."))
                } else {
                    CaloriesChart(days: d.calories, window: d.window)
                }
            }
        case .weight:
            let weight = d.weight ?? []
            ChartCard(page.title, icon: page.icon, caption: WeightChart.caption(weight, units: d.units)) {
                EmptyView()
            } content: {
                if weight.isEmpty {
                    EmptyChart(title: String(localized: "No Weigh-ins"), icon: "scalemass",
                               message: String(localized: "There are no weigh-ins in \(range)."))
                } else {
                    WeightChart(points: weight, window: d.window, units: d.units)
                }
            }
        }
    }

    private var range: String { Theme.rangePhrase(d.selection) }
    private var end: String { d.window.end.formatted(.dateTime.month(.wide).day()) }

    private func arrow(forward: Bool) -> some View {
        Button {
            withAnimation(Self.slide) { model.stepChart(forward: forward) }
        } label: {
            Image(systemName: forward ? "chevron.right" : "chevron.left")
                .font(Theme.body.weight(.bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 34, height: 34)
                .overlay(Circle().strokeBorder(Theme.border))
        }
        .buttonStyle(CardButtonStyle(shape: Circle(), resting: Theme.card))
        .shadow(color: Theme.night.opacity(0.10), radius: 6, y: 2)
        .help(forward ? "Next chart (⌘])" : "Previous chart (⌘[)")
        .accessibilityLabel(forward ? "Next chart" : "Previous chart")
    }

    private func dots(_ pages: [ChartPage], current: ChartPage) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(pages.enumerated()), id: \.element) { i, p in
                Button {
                    withAnimation(Self.slide) { model.showChart(i) }
                } label: {
                    Capsule()
                        .fill(p == current ? Theme.blue : Theme.dot)
                        .frame(width: p == current ? 20 : 7, height: 7)
                        .padding(6.5)   // a 20-pt target round each dot
                }
                .buttonStyle(DotButtonStyle())
                .help(p.title)
                .accessibilityLabel(p.title)
                .accessibilityAddTraits(p == current ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Charts")
    }
}
