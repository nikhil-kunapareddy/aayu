import SwiftUI

/// Aayu — a SwiftUI front end over a Python backend. The backend (backend/)
/// owns the Zepp data; this app asks it for numbers and draws them.
@main
struct AayuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = DashboardModel()
    @AppStorage(Pref.appearance) private var appearance = "light"

    init() {
        UserDefaults.standard.register(defaults: Pref.defaults)
        // There's one window and it always opens at launch, so ignore saved
        // window state. A stale one (e.g. after a force quit) otherwise
        // "restores" nothing and the dashboard never appears.
        UserDefaults.standard.register(defaults: ["ApplePersistenceIgnoreState": true])
    }

    var body: some Scene {
        Window("Aayu", id: "main") {
            DashboardView()
                .environment(model)
                .tint(Theme.blue)
        }
        .defaultSize(width: 1320, height: 900)
        .windowStyle(.hiddenTitleBar)   // the blue hero runs to the top edge
        .commands { DashboardCommands(model: model) }
        .onChange(of: appearance, initial: true) { _, value in Theme.apply(appearance: value) }

        Settings {
            SettingsView()
                .environment(model)
                .tint(Theme.blue)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Quit when the dashboard window closes — Aayu is a single-window app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        Backend.terminateHelper()
    }
}

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
