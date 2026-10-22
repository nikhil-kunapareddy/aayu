import Foundation
import Observation
import os

/// Dashboard state, shared by the main window, Settings and the menu commands.
@MainActor @Observable
final class DashboardModel {
    enum Phase {
        case welcome            // no folder chosen yet
        case loading            // opening the folder, nothing to show yet
        case failed(AppError)   // nothing to show: the folder couldn't be opened or drawn
        case ready(Dashboard)
    }

    private(set) var phase: Phase = .loading
    /// A failure that left the dashboard on screen (a reload or refresh),
    /// for the banner under the header. Cleared by the next success.
    private(set) var issue: AppError?
    /// True once a request the window waits on (open, reload, dashboard) has
    /// been in flight for `progressDelay`, until none is — for a progress
    /// indicator that doesn't flash on quick replies.
    private(set) var isRefreshing = false
    /// Whether the window's Zepp folder chooser is showing (⌘O, the prompts, the banner).
    var isChoosingFolder = false

    @ObservationIgnored private var selection: String?   // nil → the default range
    @ObservationIgnored private var night: String?       // Sleep Breakdown night; nil → the window's last
    @ObservationIgnored private var latest = 0           // newest dashboard request; older replies are dropped
    @ObservationIgnored private var started = false
    @ObservationIgnored private var openedFolder: String?
    @ObservationIgnored private var opening: Task<Void, Never>?
    @ObservationIgnored private var listener: Task<Void, Never>?
    @ObservationIgnored private var inFlight = 0
    @ObservationIgnored private var progressTimer: Task<Void, Never>?
    private let backend: any BackendClient
    private let defaults: UserDefaults
    private let progressDelay: Duration

    /// The app uses the real helper and the standard defaults; tests pass a
    /// fake backend, a scratch suite and a shorter `progressDelay`.
    init(backend: any BackendClient = Backend(), defaults: UserDefaults = .standard,
         progressDelay: Duration = .milliseconds(200)) {
        self.backend = backend
        self.defaults = defaults
        self.progressDelay = progressDelay
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

    /// ⌘R / Try Again: there's a folder, and it isn't still opening.
    var canReload: Bool {
        switch phase {
        case .ready, .failed: true
        case .welcome, .loading: false
        }
    }

    // ── Settings, as last saved by the views ─────────────────────────────────
    private var folder: String { defaults.string(forKey: Pref.folder) ?? "" }
    private var units: Units { defaults.string(forKey: Pref.units).flatMap(Units.init) ?? .lbs }
    private var defaultRange: DefaultRange {
        defaults.string(forKey: Pref.defaultRange).flatMap(DefaultRange.init) ?? .month
    }
    private var bedtime: ClockTime { defaults.string(forKey: Pref.bedtime).flatMap(ClockTime.init) ?? .bedtime }
    private var wakeTime: ClockTime { defaults.string(forKey: Pref.wakeTime).flatMap(ClockTime.init) ?? .wakeTime }

    // ── Loading ──────────────────────────────────────────────────────────────
    /// Open the saved folder, once, when the window first appears.
    func start() async {
        guard !started else { return }
        started = true
        await open()
    }

    /// (Re)open the folder from Settings and show its dashboard. A newer call
    /// cancels an older one still waiting — e.g. on a macOS privacy prompt —
    /// and the backend then restarts its helper rather than queue behind it.
    func open() async {
        opening?.cancel()
        let task = Task { await load() }
        opening = task
        await task.value
        if opening == task { opening = nil }
    }

    private func load() async {
        await setAutoReload(defaults.bool(forKey: Pref.autoReload))
        guard !Task.isCancelled else { return }
        let folder = folder
        guard !folder.isEmpty else {
            phase = .welcome
            issue = nil
            return
        }
        if folder != openedFolder {   // a different export starts on its default range
            openedFolder = folder
            selection = nil
            night = nil
        }
        issue = nil
        if dashboard == nil { phase = .loading }
        do {
            let status = try await tracked { try await backend.call(OpenRequest(folder: folder)) }
            guard !Task.isCancelled else { return }
            if let failure = status.failure {
                show(failure, during: "Opening the folder", replacingDashboard: true)
            } else {
                await refresh()
            }
        } catch is CancellationError {
            Log.model.debug("Opening the folder was superseded")
        } catch {
            guard !Task.isCancelled else { return }
            show(AppError(error), during: "Opening the folder", replacingDashboard: true)
        }
    }

    /// Re-fetch the dashboard (new selection, units, sleep targets, or reloaded data). A
    /// failure keeps the dashboard on screen, with the banner.
    func refresh() async {
        guard !folder.isEmpty else {
            phase = .welcome
            return
        }
        latest += 1
        let id = latest
        let request = DashboardRequest(selection: selection, units: units, defaultRange: defaultRange, night: night,
                                       bedtime: bedtime, wakeTime: wakeTime)
        do {
            let d = try await tracked { try await backend.call(request) }
            guard id == latest else {
                Log.model.debug("Dropped a stale dashboard reply")
                return
            }
            selection = d.selection
            night = d.hypnogram?.night
            phase = .ready(d)
            issue = nil
        } catch is CancellationError {
            Log.model.debug("A dashboard request was cancelled")
        } catch {
            guard id == latest else {
                Log.model.debug("Dropped a stale dashboard failure")
                return
            }
            show(AppError(error), during: "The dashboard", replacingDashboard: false)
        }
    }

    /// Re-read the folder from disk (⌘R, Try Again). With nothing on screen
    /// yet — a failed open — it opens the folder again instead.
    func reload() async {
        guard !folder.isEmpty else {
            phase = .welcome
            return
        }
        guard dashboard != nil else {
            await open()
            return
        }
        do {
            let status = try await tracked { try await backend.call(ReloadRequest()) }
            if let failure = status.failure {
                show(failure, during: "Reloading the folder", replacingDashboard: false)
                return
            }
        } catch is CancellationError {
            Log.model.debug("Reloading was cancelled")
            return
        } catch {
            show(AppError(error), during: "Reloading the folder", replacingDashboard: false)
            return
        }
        await refresh()
    }

    /// Hide the banner (the dashboard stays as it is).
    func dismissIssue() {
        issue = nil
    }

    func setAutoReload(_ enabled: Bool) async {
        let state = enabled ? "on" : "off"
        do {
            _ = try await backend.call(WatchRequest(enabled: enabled))
        } catch is CancellationError {
            Log.model.debug("Turning auto-reload \(state, privacy: .public) was cancelled")
        } catch {
            // Not shown: the dashboard works without auto-reload, and a helper
            // that's down shows up in the request that follows.
            Log.model.error("Turning auto-reload \(state, privacy: .public) failed: \(String(describing: error), privacy: .private)")
        }
    }

    /// What a folder contains, for the Settings status line. Nil if that
    /// can't be found out, or the calling task (Settings' `.task(id:)`) was cancelled.
    func status(of folder: String) async -> FolderStatus? {
        do {
            return try await backend.call(StatusRequest(folder: folder))
        } catch is CancellationError {
            Log.model.debug("A folder status check was cancelled")
            return nil
        } catch {
            Log.model.error("The folder status failed: \(String(describing: error), privacy: .private)")
            return nil
        }
    }

    /// Show `error`: in place of the page when there's no dashboard (or a new
    /// folder failed to open), otherwise in the banner over the dashboard.
    private func show(_ error: AppError, during what: String, replacingDashboard: Bool) {
        Log.model.error("\(what, privacy: .public) failed: \(String(describing: error), privacy: .private)")
        if replacingDashboard || dashboard == nil {
            phase = .failed(error)
            issue = nil
        } else {
            issue = error
        }
    }

    // ── Progress ─────────────────────────────────────────────────────────────
    /// Run `work`, counting it as a request the window waits on.
    private func tracked<T>(_ work: () async throws -> T) async rethrows -> T {
        began()
        defer { ended() }
        return try await work()
    }

    private func began() {
        inFlight += 1
        guard inFlight == 1 else { return }
        progressTimer = Task { [weak self, progressDelay] in
            do {
                try await Task.sleep(for: progressDelay)
            } catch {
                return   // everything finished in time
            }
            guard let self, !Task.isCancelled, self.inFlight > 0 else { return }
            self.isRefreshing = true
        }
    }

    private func ended() {
        inFlight -= 1
        guard inFlight == 0 else { return }
        progressTimer?.cancel()
        progressTimer = nil
        if isRefreshing { isRefreshing = false }
    }

    // ── Month picker (options run newest → oldest) ───────────────────────────
    func select(_ value: String) {
        selection = value
        night = nil   // a new window starts on its last night
        Task { await refresh() }
    }

    /// The newest calendar month on offer (not "Last 30 days").
    private var latestMonth: String? {
        dashboard?.options.first { $0 != "last30" }
    }

    /// ⌘T: whether the latest month isn't already the (requested) range.
    var canShowLatestMonth: Bool {
        guard let month = latestMonth, let d = dashboard else { return false }
        return (selection ?? d.selection) != month
    }

    func showLatestMonth() {
        guard canShowLatestMonth, let month = latestMonth else { return }
        select(month)
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

    /// Jump to `page` (⌘1…⌘4), if this dashboard has it.
    func show(_ page: ChartPage) {
        guard let i = ChartPage.available(in: dashboard).firstIndex(of: page) else { return }
        showChart(i)
    }

    /// The chart on screen, or nil without a dashboard.
    var currentChart: ChartPage? {
        guard dashboard != nil else { return nil }
        let pages = ChartPage.available(in: dashboard)
        return pages[min(chart, pages.count - 1)]
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
