import SwiftUI

/// The pale page under the header: the KPI tiles (a row of four, or 2 × 2 in a
/// narrow window) over the chart pager, which takes the height that's left
/// (at least `Theme.chartMinHeight`; a shorter window scrolls, see
/// DashboardView). Past `Theme.maxContentWidth` the content stays centred.
struct DashboardPage: View {
    let d: Dashboard

    var body: some View {
        PageContent(d: d)
            .padding(Theme.inset)
            .frame(maxWidth: Theme.maxContentWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .measuringLayoutClass()
    }
}

private struct PageContent: View {
    let d: Dashboard
    @Environment(\.layoutClass) private var layout

    var body: some View {
        VStack(spacing: Theme.gap) {
            Group {
                if layout == .narrow {
                    Grid(horizontalSpacing: Theme.gap, verticalSpacing: Theme.gap) {
                        GridRow { steps; sleep }
                        GridRow { heart; weight }
                    }
                } else {
                    HStack(spacing: Theme.gap) { steps; sleep; heart; weight }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            ChartPager(d: d)
        }
    }

    private var k: KPIs { d.kpis }
    private var range: String { Theme.rangePhrase(d.selection) }

    private var steps: some View {
        StatTile(title: String(localized: "Daily Average Steps"), badge: Theme.steps,
                 value: k.avgSteps.map { $0.formatted() }, number: k.avgSteps.map(Double.init), unit: nil,
                 spokenValue: k.avgSteps.map { String(localized: "\($0.formatted()) steps") },
                 change: k.avgStepsChangePct.map { pct in
                     ChangeLabel(pct, higherIsBetter: true) { versus(String(localized: "\($0)%")) }
                 },
                 help: String(localized: "Average steps per day in \(range), compared with \(previous)."))
    }

    private var sleep: some View {
        let hours = k.avgSleepH.map { $0.formatted(.number.precision(.fractionLength(1))) }
        return StatTile(title: String(localized: "Average Sleep"), badge: Theme.sleep,
                        value: hours, number: k.avgSleepH, unit: String(localized: "hrs"),
                        spokenValue: hours.map { String(localized: "\($0) hours") },
                        change: k.avgSleepHChange.map { h in
                            ChangeLabel(h, decimals: 1, higherIsBetter: true) { versus(String(localized: "\($0) hrs")) }
                        },
                        help: String(localized: "Average time asleep per night in \(range), compared with \(previous)."))
    }

    private var heart: some View {
        StatTile(title: String(localized: "Resting Heart Rate"), badge: Theme.heart,
                 value: k.avgRestingHr.map { $0.formatted() }, number: k.avgRestingHr.map(Double.init),
                 unit: String(localized: "bpm"),
                 spokenValue: k.avgRestingHr.map { String(localized: "\($0.formatted()) beats per minute") },
                 change: k.avgRestingHrChange.map { bpm in
                     ChangeLabel(Double(bpm), higherIsBetter: false) { versus(String(localized: "\($0) bpm")) }
                 },
                 help: String(localized: "Average resting heart rate in \(range), compared with \(previous)."))
    }

    private var weight: some View {
        let value = k.weight.map { $0.formatted(.number.precision(.fractionLength(1))) }
        return StatTile(title: String(localized: "Weight"), badge: Theme.scale,
                        value: value, number: k.weight, unit: d.units,
                        spokenValue: value.map { String(localized: "\($0) \(spokenUnits)") },
                        change: k.weightChange.map { w in
                            ChangeLabel(w, decimals: 1, higherIsBetter: nil) { across(String(localized: "\($0) \(d.units)")) }
                        },
                        help: String(localized: """
                            Your last weigh-in by the end of \(range); the change runs from its first weigh-in to its last.
                            """))
    }

    /// The month before the window ("April"), or nil for "Last 30 days".
    private var previousMonth: String? {
        guard d.selection != "last30",
              let start = Calendar.current.date(byAdding: .month, value: -1, to: d.window.start) else { return nil }
        return start.formatted(.dateTime.month(.wide))
    }

    /// What the change compares with: "April" / "the 30 days before".
    private var previous: String { previousMonth ?? String(localized: "the 30 days before") }

    /// "+12% vs April" / "+12% vs the 30 days before".
    private func versus(_ amount: String) -> String {
        if let previousMonth { return String(localized: "\(amount) vs \(previousMonth)") }
        return String(localized: "\(amount) vs the 30 days before")
    }

    /// "−1.5 lbs this month" / "−1.5 lbs over 30 days".
    private func across(_ amount: String) -> String {
        d.selection == "last30" ? String(localized: "\(amount) over 30 days") : String(localized: "\(amount) this month")
    }

    private var spokenUnits: String {
        d.units == "kg" ? String(localized: "kilograms") : String(localized: "pounds")
    }
}
