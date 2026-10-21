import SwiftUI

/// The pale page under the header: a row of KPI tiles over the chart pager.
struct DashboardPage: View {
    let d: Dashboard

    var body: some View {
        let k = d.kpis
        VStack(spacing: Theme.gap) {
            HStack(spacing: Theme.gap) {
                StatTile(title: "Daily Average Steps", badge: Theme.steps,
                         value: k.avgSteps.map { $0.formatted() }, unit: nil,
                         change: k.avgStepsChangePct.map {
                             ChangeLabel($0, suffix: "% " + versus, higherIsBetter: true)
                         })
                StatTile(title: "Average Sleep", badge: Theme.sleep,
                         value: k.avgSleepH.map { $0.formatted(.number.precision(.fractionLength(1))) }, unit: "hrs",
                         change: k.avgSleepHChange.map {
                             ChangeLabel($0, decimals: 1, suffix: " hrs " + versus, higherIsBetter: true)
                         })
                StatTile(title: "Resting Heart Rate", badge: Theme.heart,
                         value: k.avgRestingHr.map(String.init), unit: "bpm",
                         change: k.avgRestingHrChange.map {
                             ChangeLabel(Double($0), suffix: " bpm " + versus, higherIsBetter: false)
                         })
                StatTile(title: "Weight", badge: Theme.scale,
                         value: k.weight.map { $0.formatted(.number.precision(.fractionLength(1))) }, unit: d.units,
                         change: k.weightChange.map {
                             ChangeLabel($0, decimals: 1, suffix: " \(d.units) " + across, higherIsBetter: nil)
                         })
            }
            .fixedSize(horizontal: false, vertical: true)
            ChartPager(d: d)
        }
        .padding(Theme.inset)
    }

    /// "vs April" / "vs the 30 days before".
    private var versus: String {
        guard d.selection != "last30", let start = Calendar.current.date(byAdding: .month, value: -1, to: d.window.start)
        else { return "vs the 30 days before" }
        return "vs " + start.formatted(.dateTime.month(.wide))
    }

    private var across: String {
        d.selection == "last30" ? "over 30 days" : "this month"
    }
}
