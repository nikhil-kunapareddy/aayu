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
                                                                       defaultRange: .month, night: nil))
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
        await fake.release(0, with: .failure(AppError.backend("old")))
        await first.value
        #expect(model.dashboard != nil)
    }

    @Test func backendErrorsAreShown() async throws {
        let model = DashboardModel(backend: FakeBackend { _ in throw AppError.backend("No folder is open.") },
                                   defaults: try Sample.defaults())
        await model.refresh()
        guard case .failed(let message) = model.phase else { Issue.record("expected .failed"); return }
        #expect(message == "No folder is open.")
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
