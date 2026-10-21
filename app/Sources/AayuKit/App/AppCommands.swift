import SwiftUI

/// View menu: month and chart navigation, and reload.
struct DashboardCommands: Commands {
    let model: DashboardModel

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            Button("Previous Month") { model.step(older: true) }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(!model.canStep(older: true))
            Button("Next Month") { model.step(older: false) }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(!model.canStep(older: false))
            Divider()
            Button("Previous Chart") { withAnimation(ChartPager.slide) { model.stepChart(forward: false) } }
                .keyboardShortcut("[")
                .disabled(model.dashboard == nil)
            Button("Next Chart") { withAnimation(ChartPager.slide) { model.stepChart(forward: true) } }
                .keyboardShortcut("]")
                .disabled(model.dashboard == nil)
            Divider()
            Button("Reload Data") { Task { await model.reload() } }
                .keyboardShortcut("r")
            Divider()
        }
    }
}
