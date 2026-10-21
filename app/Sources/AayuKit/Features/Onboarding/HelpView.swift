import SwiftUI

/// Help › Aayu Help: how to get a Zepp export onto this Mac and into Aayu,
/// plus the keyboard shortcuts. Shown in its own small window.
struct HelpView: View {
    static let windowID = "help"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    AayuLogo(size: 52)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Aayu Help")
                            .font(.title2.weight(.semibold))
                            .accessibilityAddTraits(.isHeader)
                        Text("Getting your Zepp data into Aayu")
                            .foregroundStyle(.secondary)
                    }
                }

                HelpSection("Export your data from Zepp") {
                    Step(1, "In the Zepp app on your phone, go to **Profile › Settings › Account** (in some versions, **Privacy**) and choose **Export data**.")
                    Step(2, "When the export is ready, save it to this Mac and unzip it.")
                    Step(3, "In Aayu, click **Choose Zepp Folder…** (or press ⌘O) and choose the unzipped folder: the one that contains **SLEEP**, **ACTIVITY**, **BODY** and the other data folders. You can also drag the folder onto Aayu’s welcome screen.")
                    Step(4, "If the folder is in Documents, Desktop or Downloads, macOS asks whether Aayu may read it. Click **Allow**.")
                }

                HelpSection("Keeping it up to date") {
                    Text("When you export again, choose the new folder (⌘O), or replace the files in the folder you chose. With **Reload when a new export appears** turned on in Settings, Aayu picks up the new files by itself; ⌘R reloads at any time.")
                }

                HelpSection("If Aayu finds no data") {
                    Text("Make sure you chose the folder whose subfolders are named SLEEP, ACTIVITY, BODY and so on — not the folder above it, or one of the subfolders.")
                }

                HelpSection("Privacy") {
                    Text("Aayu reads your Zepp export on this Mac. Nothing is uploaded.")
                }

                HelpSection("Keyboard shortcuts") {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                        Shortcut("⌘O", "Choose a Zepp folder")
                        Shortcut("⌘R", "Reload the data")
                        Shortcut("⌘←  ⌘→", "Previous or next month")
                        Shortcut("⌘T", "Latest month")
                        Shortcut("⌘1 – ⌘4", "Sleep, Workouts, Calories, Weight")
                        Shortcut("⌘[  ⌘]", "Previous or next chart")
                        Shortcut("⌥⌘←  ⌥⌘→", "Previous or next night")
                        Shortcut("⌘,", "Settings")
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
        .frame(width: 520)
        .frame(minHeight: 420, idealHeight: 640)
    }
}

/// A heading and its paragraphs.
private struct HelpSection<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            content
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A numbered step.
private struct Step: View {
    let number: Int
    let text: LocalizedStringKey

    init(_ number: Int, _ text: LocalizedStringKey) {
        self.number = number
        self.text = text
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(number, format: .number)
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 14, alignment: .trailing)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)   // "1, In the Zepp app…"
    }
}

/// A shortcut and what it does, as a grid row.
private struct Shortcut: View {
    let keys: String
    let action: LocalizedStringKey

    init(_ keys: String, _ action: LocalizedStringKey) {
        self.keys = keys
        self.action = action
    }

    var body: some View {
        GridRow {
            Text(verbatim: keys)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
            Text(action)
        }
    }
}
