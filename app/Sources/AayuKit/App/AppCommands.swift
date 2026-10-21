import AppKit
import SwiftUI

/// The menus: About with Aayu's own credits; File › Choose Zepp Folder…;
/// View › charts, months, nights and Reload; Help › Aayu Help.
struct DashboardCommands: Commands {
    let model: DashboardModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Aayu") { AboutPanel.show() }
        }

        CommandGroup(replacing: .newItem) {
            Button("Choose Zepp Folder…") { model.isChoosingFolder = true }
                .keyboardShortcut("o")
        }

        CommandGroup(before: .toolbar) {
            chartItems
            Divider()
            Button("Previous Month") { model.step(older: true) }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(!model.canStep(older: true))
            Button("Next Month") { model.step(older: false) }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(!model.canStep(older: false))
            Button("Latest Month") { model.showLatestMonth() }
                .keyboardShortcut("t")
                .disabled(!model.canShowLatestMonth)
            Divider()
            Button("Previous Night") { stepNight(older: true) }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .disabled(!model.canStepNight(older: true))
            Button("Next Night") { stepNight(older: false) }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .disabled(!model.canStepNight(older: false))
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
                .disabled(!model.canReload)
            Divider()
        }

        CommandGroup(replacing: .help) {
            Button("Aayu Help") { openWindow(id: HelpView.windowID) }
                .keyboardShortcut("?")
        }
    }

    /// ⌘1…⌘4: straight to a chart. Weight only when the export has body data.
    @ViewBuilder private var chartItems: some View {
        let pages = ChartPage.available(in: model.dashboard)
        Button("Sleep") { show(.sleep) }
            .keyboardShortcut("1")
            .disabled(model.dashboard == nil)
        Button("Workouts") { show(.workouts) }
            .keyboardShortcut("2")
            .disabled(model.dashboard == nil)
        Button("Calories") { show(.calories) }
            .keyboardShortcut("3")
            .disabled(model.dashboard == nil)
        if model.dashboard != nil, pages.contains(.weight) {
            Button("Weight") { show(.weight) }
                .keyboardShortcut("4")
        }
    }

    private func show(_ page: ChartPage) {
        withAnimation(ChartPager.slide) { model.show(page) }
    }

    /// A night step is only visible on Sleep Breakdown, so go there first.
    private func stepNight(older: Bool) {
        if model.currentChart != .sleep { show(.sleep) }
        model.stepNight(older: older)
    }
}

/// The standard About panel, with Aayu's own credits line.
@MainActor enum AboutPanel {
    static func show() {
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        let credits = NSAttributedString(
            string: String(localized: "Reads your Zepp export on this Mac. Nothing is uploaded."),
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: centered,
            ])
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate()
    }
}
