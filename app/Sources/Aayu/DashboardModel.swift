import Foundation
import Observation

/// Settings keys and defaults. The views bind them with @AppStorage; the model
/// reads them from UserDefaults when it talks to the backend.
enum Pref {
    static let folder = "folder"               // Zepp export folder
    static let units = "units"                 // "lbs" | "kg"
    static let defaultRange = "defaultRange"   // "month" | "last30"
    static let autoReload = "autoReload"
    static let appearance = "appearance"       // "system" | "light" | "dark"

    static let defaults: [String: Any] = [folder: "", units: "lbs", defaultRange: "month", autoReload: true,
                                          appearance: "light"]

    static var folderPath: String { UserDefaults.standard.string(forKey: folder) ?? "" }
}

/// Dashboard state, shared by the main window, Settings and the menu commands.
@MainActor @Observable
final class DashboardModel {
    enum Phase {
        case welcome            // no folder chosen yet
        case loading
        case failed(String)
        case ready(Dashboard)
    }

    private(set) var phase: Phase = .loading
    @ObservationIgnored private var selection: String?   // nil → the default range
    @ObservationIgnored private var night: String?       // Sleep Breakdown night; nil → the window's last
    @ObservationIgnored private var latest = 0           // newest dashboard request; older replies are dropped
    @ObservationIgnored private var started = false
    @ObservationIgnored private var backend: Backend!

    init() {
        backend = Backend { [weak self] event in
            guard event == "reloaded" else { return }
            Task { @MainActor in await self?.refresh() }
        }
    }

    var dashboard: Dashboard? {
        if case .ready(let d) = phase { return d }
        return nil
    }

    // ── Loading ──────────────────────────────────────────────────────────────
    /// Open the saved folder, once, when the window first appears.
    func start() async {
        guard !started else { return }
        started = true
        await open()
    }

    /// (Re)open the folder from Settings and show its dashboard.
    func open() async {
        let defaults = UserDefaults.standard
        await setAutoReload(defaults.bool(forKey: Pref.autoReload))
        let folder = Pref.folderPath
        guard !folder.isEmpty else {
            phase = .welcome
            return
        }
        if dashboard == nil { phase = .loading }
        do {
            let status: FolderStatus = try await backend.call("open", ["folder": folder])
            if let error = status.error {
                phase = .failed(error)
            } else {
                await refresh()
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Re-fetch the dashboard (new selection, units, or reloaded data).
    func refresh() async {
        let defaults = UserDefaults.standard
        guard !Pref.folderPath.isEmpty else {
            phase = .welcome
            return
        }
        latest += 1
        let id = latest
        do {
            let d: Dashboard = try await backend.call("dashboard", [
                "selection": selection ?? NSNull(),
                "units": defaults.string(forKey: Pref.units) ?? "lbs",
                "default_range": defaults.string(forKey: Pref.defaultRange) ?? "month",
                "night": night ?? NSNull(),
            ])
            guard id == latest else { return }
            selection = d.selection
            night = d.hypnogram?.night
            phase = .ready(d)
        } catch {
            guard id == latest else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    /// Re-read the folder from disk (⌘R).
    func reload() async {
        do {
            let status: FolderStatus = try await backend.call("reload")
            if let error = status.error {
                phase = .failed(error)
                return
            }
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }
        await refresh()
    }

    func setAutoReload(_ enabled: Bool) async {
        _ = try? await backend.call("watch", ["enabled": enabled], as: Backend.Ignored.self)
    }

    /// What a folder contains, for the Settings status line.
    func status(of folder: String) async -> FolderStatus? {
        try? await backend.call("status", ["folder": folder])
    }

    // ── Month picker (options run newest → oldest) ───────────────────────────
    func select(_ value: String) {
        selection = value
        night = nil   // a new window starts on its last night
        Task { await refresh() }
    }

    // ── Chart pager (pages from ChartPage.available) ─────────────────────────
    private(set) var chart = 0             // the page shown
    private(set) var chartForward = true   // the last step's direction, for the slide

    /// The next or previous chart, wrapping round.
    func stepChart(forward: Bool) {
        let n = ChartPage.available(in: dashboard).count
        chartForward = forward
        chart = (min(chart, n - 1) + (forward ? 1 : n - 1)) % n
    }

    func showChart(_ index: Int) {
        chartForward = index >= chart
        chart = index
    }

    // ── Sleep Breakdown night (nights run oldest → newest) ───────────────────
    func canStepNight(older: Bool) -> Bool {
        guard let h = dashboard?.hypnogram, let i = h.nights.firstIndex(of: night ?? h.night) else { return false }
        return older ? i > 0 : i < h.nights.count - 1
    }

    func stepNight(older: Bool) {
        guard canStepNight(older: older), let h = dashboard?.hypnogram,
              let i = h.nights.firstIndex(of: night ?? h.night) else { return }
        night = h.nights[i + (older ? -1 : 1)]
        Task { await refresh() }
    }

    /// Where the requested range sits in the options. Uses the requested
    /// `selection`, not the shown one, so quick repeated steps all count.
    private var index: Int? {
        guard let d = dashboard else { return nil }
        return d.options.firstIndex(of: selection ?? d.selection)
    }

    func canStep(older: Bool) -> Bool {
        guard let d = dashboard, let i = index else { return false }
        return older ? i < d.options.count - 1 : i > 0
    }

    func step(older: Bool) {
        guard canStep(older: older), let d = dashboard, let i = index else { return }
        select(d.options[i + (older ? 1 : -1)])
    }
}
