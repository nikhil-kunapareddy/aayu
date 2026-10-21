import SwiftUI
import UniformTypeIdentifiers
import os

/// The folder picker for the Zepp export. The main window has one (⌘O, the
/// prompts and the banner set `DashboardModel.isChoosingFolder`); Settings
/// has its own. A chosen folder is saved under `Pref.folder`, which the
/// dashboard watches and opens.
struct FolderChooser: ViewModifier {
    @Binding var isPresented: Bool
    @AppStorage(Pref.folder) private var folder = ""
    @Environment(DashboardModel.self) private var model

    func body(content: Content) -> some View {
        content.fileImporter(isPresented: $isPresented, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url):
                Self.use(url, folder: $folder, model: model)
            case .failure(let error):
                Log.app.error("The folder picker failed: \(error.localizedDescription, privacy: .private)")
            }
        }
    }

    /// Make `url` the Zepp folder. Saving a new one makes the dashboard open
    /// it; choosing the current one again (after a failure, or once macOS
    /// has granted access) opens it again, since the setting doesn't change.
    @MainActor static func use(_ url: URL, folder: Binding<String>, model: DashboardModel) {
        if url.path == folder.wrappedValue {
            Task { await model.open() }
        } else {
            folder.wrappedValue = url.path
        }
    }

    /// Whether `url` is a folder one could choose: a directory, not a file or
    /// a package such as an app.
    static func isFolder(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        do {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            return values.isDirectory == true && values.isPackage != true
        } catch {
            Log.app.info("Couldn't tell whether a dropped item is a folder: \(error.localizedDescription, privacy: .private)")
            return false
        }
    }
}

extension View {
    /// Shows the Zepp folder picker while `isPresented` is true.
    func zeppFolderChooser(isPresented: Binding<Bool>) -> some View {
        modifier(FolderChooser(isPresented: isPresented))
    }
}
