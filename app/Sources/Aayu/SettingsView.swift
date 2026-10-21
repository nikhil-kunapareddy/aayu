import SwiftUI
import UniformTypeIdentifiers

/// Settings (⌘,). Changes apply as soon as they're made, as in macOS Settings;
/// the dashboard window watches the same @AppStorage keys and refreshes.
struct SettingsView: View {
    @Environment(DashboardModel.self) private var model
    @AppStorage(Pref.folder) private var folder = ""
    @AppStorage(Pref.units) private var units = "lbs"
    @AppStorage(Pref.defaultRange) private var defaultRange = "month"
    @AppStorage(Pref.autoReload) private var autoReload = true
    @AppStorage(Pref.appearance) private var appearance = "light"
    @State private var status: FolderStatus?
    @State private var choosing = false

    var body: some View {
        Form {
            Section("Data") {
                LabeledContent("Zepp data folder") {
                    HStack {
                        Text(folder.isEmpty ? "None" : (folder as NSString).abbreviatingWithTildeInPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(folder.isEmpty ? .secondary : .primary)
                            .help(folder)
                        Button("Choose…") { choosing = true }
                    }
                }
                if let status { statusLine(status) }
                Toggle("Reload when a new export appears", isOn: $autoReload)
            }
            Section("Display") {
                Picker("Appearance", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
                Picker("Weight units", selection: $units) {
                    Text("lbs").tag("lbs")
                    Text("kg").tag("kg")
                }
                .pickerStyle(.segmented)
                Picker("Open on", selection: $defaultRange) {
                    Text("Latest month").tag("month")
                    Text("Last 30 days").tag("last30")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { folder = url.path }
        }
        .task(id: folder) {
            status = folder.isEmpty ? nil : await model.status(of: folder)
        }
    }

    private func statusLine(_ s: FolderStatus) -> some View {
        let ok = s.exists && !s.found.isEmpty
        let text = !s.exists ? "This folder doesn't exist any more."
            : s.found.isEmpty ? "No Zepp data here. Choose the folder that contains SLEEP, ACTIVITY, BODY…"
            : "Found \(s.found.count) of \(s.total): " + s.found.joined(separator: ", ")
        return Label {
            Text(text).foregroundStyle(.secondary)
        } icon: {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? .green : .orange)
        }
        .font(.callout)
    }
}
