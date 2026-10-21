import SwiftUI

/// First launch, or a folder that can't be shown: the logo, a message, and a
/// button to choose the Zepp export folder.
struct FolderPrompt: View {
    let title: String
    let message: String
    @State private var choosing = false

    var body: some View {
        ZStack {
            HeaderBackground()
            VStack(spacing: 16) {
                AayuLogo(size: 112)
                Text(title)
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(.white)
                Text(message)
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
                HStack(spacing: 10) {
                    Button { choosing = true } label: {
                        Text("Choose Zepp Folder")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.night)
                            .padding(.horizontal, 32)
                            .frame(height: 50)
                            .background(.white, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    SettingsLink {
                        Image(systemName: "gearshape")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 50, height: 50)
                            .frosted(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Settings (⌘,)")
                }
                .padding(.top, 10)
            }
            .padding(40)
        }
        .zeppFolderChooser(isPresented: $choosing)
    }
}
