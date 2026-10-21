import SwiftUI

/// The main window: a dark header (greeting, month control, Sleep Score panel)
/// over a pale page of KPI tiles and chart cards.
struct DashboardView: View {
    @Environment(DashboardModel.self) private var model
    @AppStorage(Pref.folder) private var folder = ""
    @AppStorage(Pref.units) private var units = Units.lbs
    @AppStorage(Pref.autoReload) private var autoReload = true

    var body: some View {
        content
            .frame(minWidth: 1180, minHeight: 860)
            .ignoresSafeArea()   // the header runs up under the traffic lights
            .task { await model.start() }
            .onChange(of: folder) { Task { await model.open() } }
            .onChange(of: units) { Task { await model.refresh() } }
            .onChange(of: autoReload) { _, enabled in Task { await model.setAutoReload(enabled) } }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .welcome:
            FolderPrompt(title: "Welcome to Aayu",
                         message: "Choose the folder you exported from the Zepp app: the one that "
                             + "contains SLEEP, ACTIVITY, BODY and the other data folders.")
        case .loading:
            ZStack {
                HeaderBackground()
                ProgressView().controlSize(.large).tint(.white)
            }
        case .failed(let message):
            FolderPrompt(title: "Can't Show Your Data", message: message)
        case .ready(let dashboard):
            VStack(spacing: 0) {
                Header(d: dashboard)
                DashboardPage(d: dashboard)
            }
            .background(Theme.page)
        }
    }
}
