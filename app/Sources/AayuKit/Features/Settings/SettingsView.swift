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
    @AppStorage(Pref.bedtime) private var bedtime = ClockTime.bedtime
    @AppStorage(Pref.wakeTime) private var wakeTime = ClockTime.wakeTime
    @AppStorage(Pref.birthDate) private var birthDate = ""
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
            Section {
                DatePicker("Target bedtime", selection: date($bedtime), displayedComponents: .hourAndMinute)
                DatePicker("Target wake time", selection: date($wakeTime), displayedComponents: .hourAndMinute)
            } header: {
                Text("Sleep Score")
            } footer: {
                Text("The score’s timing compares your average bed and wake times with these.")
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Date of birth") {
                    if let day = CalendarDay(rawValue: birthDate) {
                        HStack(spacing: 8) {
                            DatePicker("Date of birth", selection: date(day), in: Self.birthRange,
                                       displayedComponents: .date)
                                .labelsHidden()
                            Button("Clear") { birthDate = "" }
                        }
                    } else {
                        Button("Set…") { birthDate = suggestedBirthDate.rawValue }
                    }
                }
            } header: {
                Text("Bio Age")
            } footer: {
                Text(birthDate.isEmpty
                     ? "Not set: your bio age uses the birth month in your Zepp profile, if it has one."
                     : "Your bio age counts from this date. It stays on this Mac.")
                    .foregroundStyle(.secondary)
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

    /// A DatePicker's binding to the stored birth date.
    private func date(_ day: CalendarDay) -> Binding<Date> {
        Binding(get: { day.date() }, set: { birthDate = CalendarDay($0).rawValue })
    }

    /// Where "Set…" starts: the date the dashboard's bio age used (the Zepp profile's), else 1 January 1990.
    private var suggestedBirthDate: CalendarDay {
        model.dashboard?.bioAge.flatMap { CalendarDay(rawValue: $0.birthDate) }
            ?? CalendarDay(year: 1990, month: 1, day: 1) ?? CalendarDay(Date.now)
    }

    /// 1 January 1900 to today.
    private static var birthRange: ClosedRange<Date> {
        (CalendarDay(year: 1900, month: 1, day: 1)?.date() ?? .distantPast)...Date.now
    }

    /// A DatePicker's binding to a stored time of day.
    private func date(_ time: Binding<ClockTime>) -> Binding<Date> {
        Binding(get: { time.wrappedValue.date() }, set: { time.wrappedValue = ClockTime($0) })
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
