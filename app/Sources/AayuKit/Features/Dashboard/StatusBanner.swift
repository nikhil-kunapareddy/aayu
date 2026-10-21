import SwiftUI

/// A failure that left the dashboard on screen — a reload, an auto-reload or
/// a refresh — just under the header: what happened, Try Again (⌘R, the
/// menu's Reload), Choose Folder…, and the raw details behind a disclosure.
/// VoiceOver announces it when it appears or changes.
struct StatusBanner: View {
    let error: AppError
    @Environment(DashboardModel.self) private var model
    @State private var showsDetails = false

    /// The warning symbol's colour: the palette's "worse" orange (DesignSystem
    /// has no dedicated warning token).
    private static let warning = Theme.down

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Self.warning)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(error.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(sentence)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.sub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Button("Choose Folder…") { model.isChoosingFolder = true }
                    .help("Choose another Zepp export folder (⌘O)")
                Button("Try Again") { Task { await model.reload() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canReload)
                    .help("Read the folder again (⌘R)")
                Button { model.dismissIssue() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.sub)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
                .help("Dismiss")
            }
            if let details = error.details {
                DisclosureGroup("Details", isExpanded: $showsDetails) {
                    Text(details)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.sub)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
                .font(.system(size: 11))
                .foregroundStyle(Theme.sub)
                .padding(.leading, 30)   // under the text, past the symbol
            }
        }
        .card(padding: 14)
        .padding(.horizontal, Theme.inset)
        .padding(.top, Theme.inset)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(error.title)
        .onChange(of: error, initial: true) { _, error in
            showsDetails = false
            AccessibilityNotification.Announcement(Self.announcement(for: error)).post()
        }
    }

    /// What happened and what to do, as shown.
    private var sentence: String {
        Self.sentence(for: error)
    }

    private static func sentence(for error: AppError) -> String {
        let message = error.errorDescription ?? ""
        guard let suggestion = error.recoverySuggestion else { return message }
        return String(localized: "\(message) \(suggestion)", comment: "An error's message, then what to do about it")
    }

    private static func announcement(for error: AppError) -> String {
        String(localized: "\(error.title): \(sentence(for: error))", comment: "VoiceOver: an error's title, then its message")
    }
}
