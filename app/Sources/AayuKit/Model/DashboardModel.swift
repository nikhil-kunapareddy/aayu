import Foundation
import Observation
import os

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
    @ObservationIgnored private var listener: Task<Void, Never>?
    private let backend: any BackendClient
    private let defaults: UserDefaults

    /// The app uses the real helper and the standard defaults; tests pass a
    /// fake backend and a scratch suite.
    init(backend: any BackendClient = Backend(), defaults: UserDefaults = .standard) {
        self.backend = backend
        self.defaults = defaults
        // Ends when the backend goes away (its event stream finishes).
        listener = Task { [weak self, events = backend.events] in
            for await event in events where event == "reloaded" {
                await self?.refresh()
            }
        }
    }

    var dashboard: Dashboard? {
        if case .ready(let d) = phase { return d }
        return nil
    }

    // ── Settings, as last saved by the views ─────────────────────────────────
    private var folder: String { defaults.string(forKey: Pref.folder) ?? "" }
    private var units: Units { defaults.string(forKey: Pref.units).flatMap(Units.init) ?? .lbs }
    private var defaultRange: DefaultRange {
        defaults.string(forKey: Pref.defaultRange).flatMap(DefaultRange.init) ?? .month
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
        await setAutoReload(defaults.bool(forKey: Pref.autoReload))
        let folder = folder
        guard !folder.isEmpty else {
            phase = .welcome
            return
        }
        if dashboard == nil { phase = .loading }
        do {
            let status = try await backend.call(OpenRequest(folder: folder))
            if let error = status.error {
                Log.model.error("The folder didn't load: \(error, privacy: .private)")
                phase = .failed(error)
            } else {
                await refresh()
            }
        } catch {
            Log.model.error("Opening the folder failed: \(error.localizedDescription, privacy: .private)")
            phase = .failed(error.localizedDescription)
        }
    }

    /// Re-fetch the dashboard (new selection, units, or reloaded data).
    func refresh() async {
        guard !folder.isEmpty else {
            phase = .welcome
            return
        }
        latest += 1
        let id = latest
        let request = DashboardRequest(selection: selection, units: units, defaultRange: defaultRange, night: night)
        do {
            let d = try await backend.call(request)
            guard id == latest else {
                Log.model.debug("Dropped a stale dashboard reply")
                return
            }
            selection = d.selection
            night = d.hypnogram?.night
            phase = .ready(d)
        } catch {
            guard id == latest else { return }
            Log.model.error("The dashboard failed: \(error.localizedDescription, privacy: .private)")
            phase = .failed(error.localizedDescription)
        }
    }

    /// Re-read the folder from disk (⌘R).
    func reload() async {
        do {
            let status = try await backend.call(ReloadRequest())
            if let error = status.error {
                Log.model.error("The folder didn't reload: \(error, privacy: .private)")
                phase = .failed(error)
                return
            }
        } catch {
            Log.model.error("Reloading failed: \(error.localizedDescription, privacy: .private)")
            phase = .failed(error.localizedDescription)
            return
        }
        await refresh()
    }

    func setAutoReload(_ enabled: Bool) async {
        do {
            _ = try await backend.call(WatchRequest(enabled: enabled))
        } catch {
            let state = enabled ? "on" : "off"
            Log.model.error("Turning auto-reload \(state, privacy: .public) failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    /// What a folder contains, for the Settings status line.
    func status(of folder: String) async -> FolderStatus? {
        do {
            return try await backend.call(StatusRequest(folder: folder))
        } catch {
            Log.model.error("The folder status failed: \(error.localizedDescription, privacy: .private)")
            return nil
        }
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
