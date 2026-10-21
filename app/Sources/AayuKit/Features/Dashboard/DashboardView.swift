import SwiftUI

/// The main window: a dark header (greeting, month control, Sleep Score panel)
/// over a pale page of KPI tiles and chart cards. Before there's a dashboard
/// it shows the welcome prompt, the loading screen or a failure; a failure
/// while a dashboard is up shows as a banner under the header instead.
struct DashboardView: View {
    @Environment(DashboardModel.self) private var model
    @AppStorage(Pref.folder) private var folder = ""
    @AppStorage(Pref.units) private var units = Units.lbs
    @AppStorage(Pref.autoReload) private var autoReload = true

    var body: some View {
        @Bindable var model = model

        content
            .frame(minWidth: 720, minHeight: 600)
            .ignoresSafeArea()   // the header runs up under the traffic lights
            .zeppFolderChooser(isPresented: $model.isChoosingFolder)   // ⌘O, the prompts, the banner
            .task { await model.start() }
            .onChange(of: folder) { Task { await model.open() } }
            .onChange(of: units) { Task { await model.refresh() } }
            .onChange(of: autoReload) { _, enabled in Task { await model.setAutoReload(enabled) } }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .welcome:
            FolderPrompt(title: String(localized: "Welcome to Aayu"),
                         message: String(localized: """
                             Choose the folder you exported from the Zepp app: the one that contains SLEEP, \
                             ACTIVITY, BODY and the other data folders.
                             """))
        case .loading:
            LoadingView()
        case .failed(let error):
            FolderPrompt(error: error) { Task { await model.reload() } }
        case .ready(let dashboard):
            VStack(spacing: 0) {
                Header(d: dashboard)
                if let issue = model.issue {
                    StatusBanner(error: issue)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                DashboardPage(d: dashboard)
            }
            .animation(.easeInOut(duration: 0.2), value: model.issue)
            .background(Theme.page)
        }
    }
}
