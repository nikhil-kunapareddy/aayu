import SwiftUI
import UniformTypeIdentifiers

/// The folder picker for the Zepp export, shared by the welcome prompt and
/// Settings. A chosen folder is saved under `Pref.folder`; the dashboard
/// watches that key and opens it.
struct FolderChooser: ViewModifier {
    @Binding var isPresented: Bool
    @AppStorage(Pref.folder) private var folder = ""

    func body(content: Content) -> some View {
        content.fileImporter(isPresented: $isPresented, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { folder = url.path }
        }
    }
}

extension View {
    /// Shows the Zepp folder picker while `isPresented` is true.
    func zeppFolderChooser(isPresented: Binding<Bool>) -> some View {
        modifier(FolderChooser(isPresented: isPresented))
    }
}
