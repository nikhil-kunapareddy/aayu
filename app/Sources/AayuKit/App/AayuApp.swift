import SwiftUI

/// Aayu — a SwiftUI front end over a Python backend. The backend (backend/)
/// owns the Zepp data; this app asks it for numbers and draws them.
/// Started by the `Aayu` executable (Sources/Aayu/main.swift).
public struct AayuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = DashboardModel()
    @AppStorage(Pref.appearance) private var appearance = Appearance.light

    public init() {
        UserDefaults.standard.register(defaults: Pref.defaults)
        // There's one window and it always opens at launch, so ignore saved
        // window state. A stale one (e.g. after a force quit) otherwise
        // "restores" nothing and the dashboard never appears.
        UserDefaults.standard.register(defaults: ["ApplePersistenceIgnoreState": true])
    }

    public var body: some Scene {
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
    func applicationDidFinishLaunching(_ notification: Notification) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        Log.app.notice("Aayu \(version, privacy: .public) launched")
    }

    /// Quit when the dashboard window closes — Aayu is a single-window app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        Log.app.notice("Aayu quitting")
        Backend.terminateHelper()
    }
}
