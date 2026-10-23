import SwiftUI
import GoogleSignIn

@main struct PaperlyApp: App {
    @State private var container: AppContainer?
    @State private var startupError: String?
    @State private var pendingImport: URL?
    @State private var pendingShortcut: PaperlyShortcut?
    @AppStorage("appearance") private var appearance = "system"
    var body: some Scene {
        WindowGroup {
            Group {
                if let container { LibraryView(model: container.library, sync: container.sync, account: container.account, shortcuts: container.shortcuts) }
                else if let startupError { ContentUnavailableView("Could not open local storage", systemImage: "externaldrive.badge.exclamationmark", description: Text(startupError)) }
                else { ProgressView("Opening Paperly…") }
            }
            .tint(.blue)
            .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
            .task {
                guard container == nil else { return }
                do {
                    let root = URL.documentsDirectory.appendingPathComponent("Paperly", isDirectory: true)
                    let repo = try await Task.detached { try NotebookRepository(root: root) }.value
                    let ready = AppContainer(repository: repo, root: root)
                    await ready.library.restoreIncoming()
                    container = ready
                    if let url = pendingImport { pendingImport = nil; await ready.library.importFile(url) }
                    if let shortcut = pendingShortcut { pendingShortcut = nil; ready.shortcuts.pending = shortcut }
                } catch { startupError = error.localizedDescription }
            }
            .onOpenURL { url in
                if let shortcut = PaperlyShortcut(url: url) {
                    if let container { container.shortcuts.pending = shortcut }
                    else { pendingShortcut = shortcut }
                } else if !GIDSignIn.sharedInstance.handle(url), url.isFileURL {
                    if let container { Task { await container.library.importFile(url) } }
                    else { pendingImport = url }
                }
            }
        }
    }
}

@MainActor final class AppContainer {
    let library: LibraryViewModel
    let account: GoogleAccount
    let sync: SyncService
    let shortcuts = ShortcutRouter()
    init(repository: NotebookRepository, root: URL) {
        account = GoogleAccount(); library = LibraryViewModel(repository: repository)
        sync = SyncService(repository: repository, account: account, stateDirectory: root.appendingPathComponent("Transfers"))
    }
}

enum PaperlyShortcut: String {
    case workspace
    case newText = "new-text"
    case audio

    init?(url: URL) {
        guard url.scheme == "paperly", let host = url.host else { return nil }
        self.init(rawValue: host)
    }
}

@MainActor @Observable final class ShortcutRouter {
    var pending: PaperlyShortcut?
}

struct ShareItem: Identifiable { let id = UUID(); var url: URL }
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}
