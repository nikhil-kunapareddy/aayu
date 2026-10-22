import AppKit
import SwiftUI

/// Settings (⌘,). Changes apply as soon as they're made, as in macOS Settings;
/// the dashboard window watches the same @AppStorage keys and refreshes.
/// Controls use the system accent color.
struct SettingsView: View {
    @Environment(DashboardModel.self) private var model
    @AppStorage(Pref.folder) private var folder = ""
    @AppStorage(Pref.units) private var units = Units.lbs
    @AppStorage(Pref.defaultRange) private var defaultRange = DefaultRange.month
    @AppStorage(Pref.autoReload) private var autoReload = true
    @AppStorage(Pref.appearance) private var appearance = Appearance.light
    @State private var status: FolderStatus?
    @State private var choosing = false

    var body: some View {
        Form {
            Section("Data") {
                LabeledContent("Zepp data folder") {
                    HStack(spacing: 6) {
                        if !folder.isEmpty {
                            Image(nsImage: Self.icon(for: folder))
                                .resizable()
                                .frame(width: 16, height: 16)
                                .accessibilityHidden(true)
                        }
                        Text(folder.isEmpty ? "None" : (folder as NSString).abbreviatingWithTildeInPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(folder.isEmpty ? .secondary : .primary)
                            .help(folder)
                    }
                }
                if let status { statusLine(status) }
                HStack {
                    Spacer()
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folder)])
                    }
                    .disabled(folder.isEmpty || status?.exists == false)
                    Button("Choose…") { choosing = true }
                }
                Toggle("Reload when a new export appears", isOn: $autoReload)
            }
            Section("Display") {
                Picker("Appearance", selection: $appearance) {
                    Text("System").tag(Appearance.system)
                    Text("Light").tag(Appearance.light)
                    Text("Dark").tag(Appearance.dark)
                }
                .pickerStyle(.segmented)
                Picker("Weight units", selection: $units) {
                    Text("lbs").tag(Units.lbs)
                    Text("kg").tag(Units.kg)
                }
                .pickerStyle(.segmented)
                Picker("Open on", selection: $defaultRange) {
                    Text("Latest month").tag(DefaultRange.month)
                    Text("Last 30 days").tag(DefaultRange.last30)
                }
            }
        }
        .formStyle(.grouped)
        // The dashboard's background, behind the form and the title bar.
        .scrollContentBackground(.hidden)
        .containerBackground(for: .window) { WindowBackground() }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        .zeppFolderChooser(isPresented: $choosing)
        .task(id: folder) {
            status = folder.isEmpty ? nil : await model.status(of: folder)
        }
    }

    /// The folder's icon as Finder shows it (a plain folder if it's gone).
    static func icon(for path: String) -> NSImage {
        FileManager.default.fileExists(atPath: path) ? NSWorkspace.shared.icon(forFile: path)
            : NSWorkspace.shared.icon(for: .folder)
    }

    private func statusLine(_ s: FolderStatus) -> some View {
        let ok = s.exists && !s.found.isEmpty
        let text = !s.exists ? String(localized: "This folder doesn’t exist any more.")
            : s.found.isEmpty ? String(localized: "No Zepp data here. Choose the folder that contains SLEEP, ACTIVITY, BODY…")
            : String(localized: "Found \(s.found.count) of \(s.total): \(s.found.formatted(.list(type: .and, width: .narrow)))")
        return Label {
            Text(text).foregroundStyle(.secondary)
        } icon: {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? .green : .orange)
        }
        .font(.callout)
    }
}
