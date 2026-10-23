import Foundation
import Observation

@MainActor @Observable final class SyncService {
    let repository: NotebookRepository
    let drive: DriveClient
    let account: GoogleAccount
    var status = "Stored on this device"
    var running = false
    var lastSync: Date?
    var error: String?
    var conflicts: [RemoteSnapshot] = []
    private(set) var localNotebookIDs: Set<UUID> = []
    /// Foreground sync defers notebooks currently being edited to avoid replacing a live canvas.
    var openNotebook: UUID?
    private var loop: Task<Void, Never>?
    init(repository: NotebookRepository, account: GoogleAccount, stateDirectory: URL) {
        self.repository = repository; self.account = account; self.drive = DriveClient(account: account, stateDirectory: stateDirectory)
    }
    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            await self?.account.restore()
            var failures = 0
            while !Task.isCancelled {
                if let self, self.account.email != nil {
                    await self.sync()
                    failures = self.error == nil ? 0 : min(failures + 1, 8)
                }
                let delay = failures == 0 ? 20.0 : min(300, pow(2, Double(failures)) + Double.random(in: 0...1))
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }
    func sync() async {
        guard !running, account.email != nil else { return }
        running = true; status = "Syncing…"; error = nil
        defer { running = false }
        do {
            let folder = try await drive.folder()
            let appearances = try await drive.syncFolderAppearances(repository.folderAppearances(), parent: folder)
            try await repository.mergeFolderAppearances(appearances)
            var remote = try await drive.snapshots()
            let local = try await repository.list()
            localNotebookIDs = Set(local.map(\.id))
            let grouped = Dictionary(grouping: remote.filter { $0.notebookID != nil }, by: { $0.notebookID! })
            conflicts = []
            for item in local where item.id != openNotebook {
                let heads = RemoteSnapshot.heads(grouped[item.id] ?? [])
                if heads.count > 1 {
                    conflicts += heads
                    try await record(item, state: "Conflict — both versions kept"); continue
                }
                let head = heads.first
                switch SyncDecision.resolve(local: item.manifest.generation, base: item.baseGeneration, remote: head?.generation) {
                case .conflict:
                    if let head { conflicts.append(head) }
                    try await record(item, state: "Conflict — both versions kept")
                case .unchanged:
                    try await repository.setSync(item.id, base: head?.generation, remote: head?.id, version: head?.version, state: "Synced")
                case .download:
                    guard let head else { continue }
                    let bytes = try await drive.download(head.id)
                    let archive = try NotebookArchive.decode(bytes)
                    guard archive.manifest.id == item.id, archive.manifest.generation == head.generation else { throw DocumentError.invalidManifest }
                    // Recheck after the network suspension: never replace newly written local strokes.
                    let current = try await repository.load(item.id)
                    guard current.generation == item.manifest.generation, openNotebook != item.id else { continue }
                    _ = try await repository.importArchive(bytes, asCopy: false)
                    try await repository.setSync(item.id, base: head.generation, remote: head.id, version: head.version, state: "Synced")
                case .upload:
                    let bytes = try await repository.exportData(item.id)
                    let snapshot = try NotebookArchive.decode(bytes)
                    let uploaded = try await drive.upload(data: bytes, manifest: snapshot.manifest, parent: item.baseGeneration, folder: folder)
                    remote.append(uploaded)
                    try await repository.setSync(item.id, base: snapshot.manifest.generation, remote: uploaded.id, version: uploaded.version, state: "Synced")
                }
            }
            // Discover notebooks created on other devices. Multi-head histories are left visible as conflicts.
            let localIDs = Set(local.map(\.id))
            for (id, snapshots) in grouped where !localIDs.contains(id) {
                let heads = RemoteSnapshot.heads(snapshots)
                guard heads.count == 1, let head = heads.first else { conflicts += heads; continue }
                let bytes = try await drive.download(head.id)
                let archive = try NotebookArchive.decode(bytes)
                guard archive.manifest.id == id, archive.manifest.generation == head.generation else { throw DocumentError.invalidManifest }
                _ = try await repository.importArchive(bytes, asCopy: false)
                try await repository.setSync(id, base: head.generation, remote: head.id, version: head.version, state: "Synced")
            }
            lastSync = Date()
            let hasOpenChanges = local.contains { $0.id == openNotebook && $0.manifest.generation != $0.baseGeneration }
            status = !conflicts.isEmpty ? "Conflicts need review" : hasOpenChanges ? "Writing locally · sync after closing" : "Synced with Google Drive"
        } catch {
            self.error = error.localizedDescription; status = "Waiting to retry · saved locally"
        }
    }
    func keepLocalAsCurrent(_ id: UUID) async {
        guard !running, openNotebook != id else { return }
        running = true; error = nil
        do {
            let all = try await drive.snapshots()
            let heads = RemoteSnapshot.heads(all.filter { $0.notebookID == id })
            let previous = try await repository.load(id)
            _ = try await repository.checkpoint(id)
            let bytes = try await repository.exportData(id)
            let archive = try NotebookArchive.decode(bytes)
            let folder = try await drive.folder()
            let uploaded = try await drive.upload(data: bytes, manifest: archive.manifest, parent: previous.generation, folder: folder, ancestors: heads.compactMap(\.generation))
            try await repository.setSync(id, base: archive.manifest.generation, remote: uploaded.id, version: uploaded.version, state: "Synced")
            conflicts.removeAll { $0.notebookID == id }
            status = "Local version kept; previous versions remain in Drive"
        } catch { self.error = error.localizedDescription; status = "Could not resolve — all versions kept" }
        running = false
    }
    func keepConflictAsCopy(_ snapshot: RemoteSnapshot) async {
        do { let bytes = try await drive.download(snapshot.id); _ = try await repository.importArchive(bytes); status = "Remote version saved as a separate notebook" }
        catch { self.error = error.localizedDescription }
    }
    private func record(_ item: NotebookSummary, state: String) async throws {
        try await repository.setSync(item.id, base: item.baseGeneration, remote: item.remoteID, version: item.remoteVersion, state: state)
    }
}
