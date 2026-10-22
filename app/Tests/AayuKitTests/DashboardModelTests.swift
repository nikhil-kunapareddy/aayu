import Foundation
import Testing
@testable import AayuKit

@MainActor @Suite("DashboardModel", .timeLimit(.minutes(1)))
struct DashboardModelTests {
    private func loaded(_ fake: FakeBackend = FakeBackend()) async throws -> DashboardModel {
        let model = DashboardModel(backend: fake, defaults: try Sample.defaults())
        await model.refresh()
        #expect(model.dashboard != nil)
        return model
    }

    @Test func noFolderShowsTheWelcome() async throws {
        let model = DashboardModel(backend: FakeBackend(), defaults: try Sample.defaults(folder: ""))
        await model.open()
        guard case .welcome = model.phase else { Issue.record("expected .welcome"); return }
    }

    @Test func openSendsWatchThenOpenThenDashboard() async throws {
        let fake = FakeBackend()
        let model = DashboardModel(backend: fake, defaults: try Sample.defaults())
        await model.start()
        await model.start()   // only once
        #expect(await fake.methods == ["watch", "open", "dashboard"])
        #expect(await fake.dashboardRequests.first == DashboardRequest(selection: nil, units: .lbs,
                                                                       defaultRange: .month, night: nil,
                                                                       bedtime: .bedtime, wakeTime: .wakeTime))
        #expect(model.dashboard?.selection == "2026-05")
    }

    @Test(arguments: [(true, 3), (false, 4)])
    func stepChartWraps(withoutWeight: Bool, pages: Int) async throws {
        let fake = FakeBackend { _ in try Sample.dashboard(weight: !withoutWeight) }
        let model = try await loaded(fake)
        #expect(ChartPage.available(in: model.dashboard).count == pages)
        var seen: [Int] = []
        for _ in 0..<pages {
            model.stepChart(forward: true)
            seen.append(model.chart)
        }
        #expect(seen == Array(1..<pages) + [0])
        #expect(model.chartForward)
        model.stepChart(forward: false)
        #expect(model.chart == pages - 1)
        #expect(!model.chartForward)
    }

    @Test func monthSteppingStopsAtTheEnds() async throws {
        let fake = FakeBackend()
        let model = try await loaded(fake)   // options: last30, 2026-05, 2026-04, 2026-03
        #expect(model.canStep(older: true) && model.canStep(older: false))

        model.step(older: true)
        await fake.waitForDashboardRequests(2)
        #expect(await fake.dashboardRequests.last?.selection == "2026-04")
        #expect(await fake.dashboardRequests.last?.night == nil)   // a new window starts on its last night
        model.step(older: true)
        await fake.waitForDashboardRequests(3)
        #expect(await fake.dashboardRequests.last?.selection == "2026-03")
        #expect(!model.canStep(older: true))
        model.step(older: true)   // already the oldest: no request

        // Quick repeated steps all count, before any reply arrives.
        for _ in 0..<3 { model.step(older: false) }
        #expect(!model.canStep(older: false))
        model.step(older: false)   // "Last 30 days" is the newest: no request
        await fake.waitForDashboardRequests(6)
        #expect(await fake.dashboardRequests.count == 6)
        #expect(await fake.dashboardRequests.last?.selection == "last30")
    }

    @Test func nightStepping() async throws {
        let fake = FakeBackend()
        let model = try await loaded(fake)   // nights 05-29 … 05-31, showing the last
        #expect(model.canStepNight(older: true))
        #expect(!model.canStepNight(older: false))

        model.stepNight(older: true)
        await fake.waitForDashboardRequests(2)
        #expect(await fake.dashboardRequests.last?.night == "2026-05-30")
        model.stepNight(older: true)
        #expect(!model.canStepNight(older: true))
        #expect(model.canStepNight(older: false))
        model.stepNight(older: true)   // the first night: no request
        await fake.waitForDashboardRequests(3)
        #expect(await fake.dashboardRequests.map(\.night) == [nil, "2026-05-30", "2026-05-29"])
    }

    @Test func noHypnogramMeansNoNightSteps() async throws {
        let model = try await loaded(FakeBackend { _ in try Sample.dashboard(night: nil) })
        #expect(!model.canStepNight(older: true) && !model.canStepNight(older: false))
    }

    @Test func staleRepliesAreDropped() async throws {
        let fake = FakeBackend()
        await fake.hold()
        let model = DashboardModel(backend: fake, defaults: try Sample.defaults())
        let first = Task { await model.refresh() }
        await fake.waitForDashboardRequests(1)
        let second = Task { await model.refresh() }
        await fake.waitForDashboardRequests(2)

        await fake.release(1, with: .success(try Sample.dashboard(selection: "2026-04")))
        await second.value
        #expect(model.dashboard?.selection == "2026-04")

        await fake.release(0, with: .success(try Sample.dashboard(selection: "2026-03")))
        await first.value
        #expect(model.dashboard?.selection == "2026-04")
    }

    @Test func staleErrorsAreDropped() async throws {
        let fake = FakeBackend()
        await fake.hold()
        let model = DashboardModel(backend: fake, defaults: try Sample.defaults())
        let first = Task { await model.refresh() }
        await fake.waitForDashboardRequests(1)
        let second = Task { await model.refresh() }
        await fake.waitForDashboardRequests(2)
        await fake.release(1, with: .success(try Sample.dashboard()))
        await second.value
        await fake.release(0, with: .failure(AppError.backend(code: .internal, message: "old")))
        await first.value
        #expect(model.dashboard != nil)
        #expect(model.issue == nil)
    }

    @Test func withoutADashboardAFailureFillsTheWindow() async throws {
        let noFolder = AppError.backend(code: .noFolder, message: "No folder is open.")
        let model = DashboardModel(backend: FakeBackend { _ in throw noFolder }, defaults: try Sample.defaults())
        await model.refresh()
        guard case .failed(let error) = model.phase else { Issue.record("expected .failed"); return }
        #expect(error == noFolder)
        #expect(model.issue == nil)
        #expect(model.canReload)
    }

    @Test func aRefreshFailureKeepsTheDashboardAndShowsTheBanner() async throws {
        let fake = FakeBackend()
        let model = try await loaded(fake)
        await fake.setReply { _ in throw AppError.timedOut(method: "dashboard", limit: .seconds(30)) }
        await model.refresh()
        #expect(model.dashboard != nil)
        #expect(model.issue == .timedOut(method: "dashboard", limit: .seconds(30)))

        await fake.setReply { _ in try Sample.dashboard() }
        await model.refresh()
        #expect(model.issue == nil)   // the next success clears it
    }

    @Test func aReloadFailureKeepsTheDashboard() async throws {
        let fake = FakeBackend()
        let model = try await loaded(fake)
        await fake.setFolderStatus(Sample.failed(.folderMissing, "The folder /tmp/zepp doesn't exist any more."))
        await model.reload()
        #expect(model.dashboard != nil)
        #expect(model.issue == .backend(code: .folderMissing, message: "The folder /tmp/zepp doesn't exist any more."))
        #expect(await fake.methods.last == "reload")   // no dashboard request after a failed reload

        await fake.setFolderStatus(Sample.loaded)
        await model.reload()
        #expect(model.issue == nil)
        #expect(await fake.methods.suffix(2) == ["reload", "dashboard"])

        await fake.setFolderStatus(Sample.failed(.unreadable))
        await model.reload()
        #expect(model.issue != nil)
        model.dismissIssue()
        #expect(model.issue == nil && model.dashboard != nil)
    }

    @Test func aFolderThatFailsToOpenReplacesTheDashboard() async throws {
        let fake = FakeBackend()
        let model = DashboardModel(backend: fake, defaults: try Sample.defaults())
        await model.open()
        #expect(model.dashboard != nil)
        await fake.setFolderStatus(Sample.failed(.noData))
        await model.open()   // e.g. a newly chosen folder with no export in it
        guard case .failed(let error) = model.phase else { Issue.record("expected .failed"); return }
        #expect(error.suggestsChoosingFolder)
    }

    @Test func tryAgainAfterAFailedOpenOpensAgain() async throws {
        let fake = FakeBackend()
        await fake.setFolderStatus(Sample.failed(.noData))
        let model = DashboardModel(backend: fake, defaults: try Sample.defaults())
        await model.open()
        guard case .failed = model.phase else { Issue.record("expected .failed"); return }
        await fake.setFolderStatus(Sample.loaded)
        await model.reload()
        #expect(model.dashboard != nil)
        #expect(await fake.calls("open") == 2)
        #expect(await fake.calls("reload") == 0)
    }

    @Test func aNewOpenCancelsTheOneStillWaiting() async throws {
        let fake = FakeBackend()
        await fake.setOpenDelay(.seconds(3600))   // as if stuck on a privacy prompt
        let model = DashboardModel(backend: fake, defaults: try Sample.defaults())
        let first = Task { await model.open() }
        await fake.waitFor("open")
        guard case .loading = model.phase else { Issue.record("expected .loading"); return }

        await fake.setOpenDelay(nil)
        await model.open()
        await first.value   // returns: cancelled, not left waiting
        #expect(model.dashboard != nil)
        #expect(await fake.calls("open") == 2)
    }

    @Test func isRefreshingOnlyOnceARequestIsSlow() async throws {
        let fake = FakeBackend()
        let model = DashboardModel(backend: fake, defaults: try Sample.defaults(), progressDelay: .milliseconds(50))
        await model.refresh()   // quick: never shows progress
        try await Task.sleep(for: .milliseconds(150))
        #expect(!model.isRefreshing)

        await fake.hold()
        let slow = Task { await model.refresh() }
        await fake.waitForDashboardRequests(1)
        try await eventually("isRefreshing turns on") { model.isRefreshing }
        await fake.release(0, with: .success(try Sample.dashboard()))
        await slow.value
        #expect(!model.isRefreshing)
    }

    @Test func canReloadFollowsThePhase() async throws {
        let welcome = DashboardModel(backend: FakeBackend(), defaults: try Sample.defaults(folder: ""))
        #expect(!welcome.canReload)   // still .loading
        await welcome.open()
        #expect(!welcome.canReload)   // .welcome
        let model = try await loaded()
        #expect(model.canReload)
    }

    @Test func latestMonth() async throws {
        let fake = FakeBackend()
        let model = try await loaded(fake)   // 2026-05, the latest month
        #expect(!model.canShowLatestMonth)
        model.step(older: true)
        await fake.waitForDashboardRequests(2)
        #expect(model.canShowLatestMonth)
        model.showLatestMonth()
        await fake.waitForDashboardRequests(3)
        #expect(await fake.dashboardRequests.last?.selection == "2026-05")
        #expect(!model.canShowLatestMonth)
    }

    @Test(arguments: [true, false])
    func showChartByPage(withWeight: Bool) async throws {
        let model = try await loaded(FakeBackend { _ in try Sample.dashboard(weight: withWeight) })
        #expect(model.currentChart == .sleep)
        model.show(.calories)
        #expect(model.chart == 2 && model.currentChart == .calories)
        model.show(.weight)
        #expect(model.currentChart == (withWeight ? .weight : .calories))
        model.show(.sleep)
        #expect(model.chart == 0 && !model.chartForward)
    }

    @Test func aNewFolderStartsOnItsDefaultRange() async throws {
        let fake = FakeBackend()
        let defaults = try Sample.defaults()
        let model = DashboardModel(backend: fake, defaults: defaults)
        await model.open()
        model.step(older: true)
        await fake.waitForDashboardRequests(2)
        defaults.set("/tmp/other", forKey: Pref.folder)
        await model.open()
        #expect(await fake.dashboardRequests.last == DashboardRequest(selection: nil, units: .lbs,
                                                                      defaultRange: .month, night: nil,
                                                                      bedtime: .bedtime, wakeTime: .wakeTime))
    }

    @Test func refreshSendsTheSavedSleepTargets() async throws {
        let fake = FakeBackend()
        let defaults = try Sample.defaults()
        defaults.set("00:15", forKey: Pref.bedtime)
        defaults.set("not a time", forKey: Pref.wakeTime)   // unreadable → the default
        let model = DashboardModel(backend: fake, defaults: defaults)
        await model.open()
        let request = try #require(await fake.dashboardRequests.last)
        #expect(request.bedtime == ClockTime(hour: 0, minute: 15) && request.wakeTime == .wakeTime)
    }

    @Test func reloadedEventRefreshes() async throws {
        let fake = FakeBackend()
        let model = try await loaded(fake)
        await fake.push("reloaded")
        await fake.waitForDashboardRequests(2)
        #expect(await fake.methods.last == "dashboard")
        withExtendedLifetime(model) {}   // the listener holds the model weakly
    }
}
