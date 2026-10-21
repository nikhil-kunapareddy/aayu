import SwiftUI

/// While the folder opens, before there's a dashboard: the logo and a spinner
/// on the header gradient. If it takes more than `hintDelay`, it's probably a
/// macOS privacy prompt holding the helper, so say so and offer another folder.
struct LoadingView: View {
    @Environment(DashboardModel.self) private var model
    @State private var slow = false

    static let hintDelay: Duration = .seconds(5)

    var body: some View {
        ZStack {
            HeaderBackground()
            VStack(spacing: 18) {
                AayuLogo(size: 96)
                    .accessibilityHidden(true)
                Text("Opening your Zepp export…")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                ProgressView()
                    .controlSize(.regular)
                    .environment(\.colorScheme, .dark)   // a light spinner on the dark gradient
                    .accessibilityLabel("Opening your Zepp export")
                if slow {
                    VStack(spacing: 14) {
                        Text("macOS may be asking for permission to read this folder — check for a dialog.")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 420)
                            .fixedSize(horizontal: false, vertical: true)
                        Button { model.isChoosingFolder = true } label: {
                            Text("Choose Another Folder…")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 22)
                                .frame(height: 40)
                                .frosted(Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .transition(.opacity)
                }
            }
            .padding(40)
            .accessibilityElement(children: .contain)
        }
        .task {
            do {
                try await Task.sleep(for: Self.hintDelay)
            } catch {
                return   // loaded (or left) in time
            }
            withAnimation(.easeInOut(duration: 0.3)) { slow = true }
            AccessibilityNotification.Announcement(String(localized: """
                macOS may be asking for permission to read this folder — check for a dialog.
                """)).post()
        }
    }
}
