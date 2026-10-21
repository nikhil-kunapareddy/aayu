import SwiftUI

/// First launch, or a folder that can't be shown (and no dashboard to keep
/// up): the logo, a message, and buttons to choose the Zepp export folder or
/// try again. A folder dropped onto the window is taken as the choice.
struct FolderPrompt: View {
    let title: String
    let message: String
    var suggestion: String?
    var details: String?
    /// Try Again; nil on the welcome screen.
    var retry: (() -> Void)?
    /// Whether Try Again leads (the failure isn't about which folder it is).
    var retryLeads = false

    @Environment(DashboardModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @AppStorage(Pref.folder) private var folder = ""
    @State private var dropTargeted = false
    @State private var showsDetails = false

    /// The welcome screen.
    init(title: String, message: String) {
        self.title = title
        self.message = message
    }

    /// A failure with nothing else to show.
    init(error: AppError, retry: @escaping () -> Void) {
        title = error.title
        message = error.errorDescription ?? ""
        suggestion = error.recoverySuggestion
        details = error.details
        self.retry = retry
        retryLeads = !error.suggestsChoosingFolder
    }

    var body: some View {
        ZStack {
            HeaderBackground()
            VStack(spacing: 16) {
                AayuLogo(size: 112)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 6) {
                    Text(message)
                    if let suggestion { Text(suggestion) }
                }
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
                .fixedSize(horizontal: false, vertical: true)
                buttons
                    .padding(.top, 10)
                Button { openWindow(id: HelpView.windowID) } label: {
                    Label("How do I export from Zepp?", systemImage: "questionmark.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.7))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Aayu Help (⌘?)")
                .padding(.top, 4)
                if let details {
                    // A disclosure, centred under the rest (a DisclosureGroup hugs the leading edge).
                    Button { withAnimation(.easeInOut(duration: 0.2)) { showsDetails.toggle() } } label: {
                        Label(showsDetails ? "Hide Details" : "Show Details",
                              systemImage: showsDetails ? "chevron.down" : "chevron.right")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.6))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(showsDetails ? Text("Expanded") : Text("Collapsed"))
                    if showsDetails {
                        Text(details)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .textSelection(.enabled)
                            .frame(maxWidth: 460)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity)
                    }
                }
            }
            .padding(40)
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: Theme.panelRadius)
                    .strokeBorder(.white.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .padding(16)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: FolderChooser.isFolder) else { return false }
            FolderChooser.use(url, folder: $folder, model: model)
            return true
        } isTargeted: { dropTargeted = $0 }
    }

    /// Choose Zepp Folder… and Try Again, whichever is likelier to help
    /// first (it gets Return), then Settings.
    private var buttons: some View {
        HStack(spacing: 10) {
            if let retry, retryLeads {
                PromptButton("Try Again", prominent: true, action: retry)
                    .keyboardShortcut(.defaultAction)
                PromptButton("Choose Zepp Folder…", prominent: false) { model.isChoosingFolder = true }
            } else {
                PromptButton("Choose Zepp Folder…", prominent: true) { model.isChoosingFolder = true }
                    .keyboardShortcut(.defaultAction)
                if let retry {
                    PromptButton("Try Again", prominent: false, action: retry)
                }
            }
            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .frosted(Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
            .help("Settings (⌘,)")
        }
    }
}

/// A capsule button on the dark gradient: white when it's the main action,
/// frosted otherwise.
private struct PromptButton: View {
    let title: LocalizedStringKey
    let prominent: Bool
    let action: () -> Void

    init(_ title: LocalizedStringKey, prominent: Bool, action: @escaping () -> Void) {
        self.title = title
        self.prominent = prominent
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(prominent ? Theme.night : .white)
                .padding(.horizontal, 32)
                .frame(height: 50)
                .background { if prominent { Capsule().fill(.white) } }
                .frosted(Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
