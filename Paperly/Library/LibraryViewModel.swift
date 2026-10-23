import SwiftUI

@MainActor @Observable final class LibraryViewModel {
    let repository: NotebookRepository
    var notebooks: [NotebookSummary] = []
    var query = "" { didSet { if query != oldValue { scheduleSearch() } } }
    var searchHits: [UUID: [NoteSearchHit]] = [:]
    var searching = false
    var indexing = false
    var recognitionError: String?
    private let searchIndexer: HandwritingIndexer
    private var searchTask: Task<Void, Never>?
    private var indexTask: Task<Void, Never>?
    private var indexRevision = 0
    enum ContentFilter: String, CaseIterable { case all = "All", text = "Text", handwriting = "Handwritten" }
    var contentFilter: ContentFilter = .all
    var folder: String?
    var sort: SortOrder = .modified
    var error: String?
    var loading = false
    var folders: [String] = []
    var folderAppearances: [String: FolderAppearance] = [:]
    var showAll = false
    var showTrash = false
    var deletedFolders: [String] { folderAppearances.values.filter(\.isDeleted).map(\.name).sorted() }
    var pendingImports: [IncomingDocument] = []
    var pendingImport: IncomingDocument? { pendingImports.first }
    var visibleFolders: [String] { (showTrash ? deletedFolders : folders).filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) } }

    enum SortOrder: String, CaseIterable { case modified = "Last modified", title = "Name", created = "Date created" }
    var filtered: [NotebookSummary] {
        notebooks.filter { item in
            let m = item.manifest
            let catalog = showTrash ? deletedFolders : folders
            let inScope = folder != nil ? m.folder == folder : (showAll || !query.isEmpty || m.folder == nil || !catalog.contains(m.folder ?? ""))
            return m.isTrashed == showTrash && inScope
                && (contentFilter == .all || (contentFilter == .text ? m.isTextDocument : !m.isTextDocument))
                && (query.isEmpty || NoteSearch.normalized(m.title).contains(NoteSearch.normalized(query)) || searchHits[item.id] != nil)
        }
            .sorted {
                switch sort {
                case .modified: $0.manifest.modifiedAt > $1.manifest.modifiedAt
                case .created: $0.manifest.createdAt > $1.manifest.createdAt
                case .title: $0.manifest.title.localizedStandardCompare($1.manifest.title) == .orderedAscending
                }
            }
    }
    init(repository: NotebookRepository) { self.repository = repository; searchIndexer = HandwritingIndexer(repository: repository) }
    func reload(indexHandwriting: Bool = true) async {
        loading = true
        do { notebooks = try await repository.list(); folders = try await repository.folders(); folderAppearances = Dictionary(uniqueKeysWithValues: try await repository.folderAppearances().map { ($0.name, $0) }) } catch { self.error = error.localizedDescription }
        loading = false
        if indexHandwriting { scheduleIndexing() } else { pauseIndexing() }
        scheduleSearch()
    }
    func pauseIndexing() {
        indexRevision += 1; indexTask?.cancel(); indexTask = nil; indexing = false
    }
    func scheduleIndexing() {
        pauseIndexing(); let ticket = indexRevision, snapshot = notebooks
        indexing = true; recognitionError = nil
        indexTask = Task { [weak self] in
            guard let self else { return }
            do { try await self.searchIndexer.refresh(snapshot) }
            catch is CancellationError { }
            catch { if self.indexRevision == ticket { self.recognitionError = error.localizedDescription } }
            guard self.indexRevision == ticket else { return }
            self.indexing = false
            await self.searchNow()
        }
    }
    private func scheduleSearch() {
        searchTask?.cancel()
        searchHits = [:]
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { searching = false; return }
        searching = true
        searchTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            await self?.searchNow()
        }
    }
    func searchNow() async {
        let current = query
        guard !current.isEmpty else { searchHits = [:]; searching = false; return }
        do {
            let hits = try await repository.search(current)
            guard query == current, !Task.isCancelled else { return }
            searchHits = Dictionary(grouping: hits, by: \.notebookID); searching = false
        } catch { if query == current { recognitionError = error.localizedDescription; searching = false } }
    }
    func setFolderColor(_ name: String, _ color: FolderColor) async {
        do {
            try await repository.setFolderColor(name, color: color)
            folderAppearances = Dictionary(uniqueKeysWithValues: try await repository.folderAppearances().map { ($0.name, $0) })
        } catch { self.error = error.localizedDescription }
    }
    func importFile(_ url: URL) async {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let root = repository.root
            let incoming = try await Task.detached { try IncomingDocument.stage(url, root: root) }.value
            pendingImports.append(incoming)
        } catch { self.error = error.localizedDescription }
    }
    func restoreIncoming() async {
        let root = repository.root
        do { pendingImports = try await Task.detached { try IncomingDocument.pending(root: root) }.value }
        catch { self.error = error.localizedDescription }
    }
    func cancelImport(_ incoming: IncomingDocument) async {
        try? await Task.detached { try incoming.remove() }.value
        pendingImports.removeAll { $0.id == incoming.id }
    }
    func finishImport(_ incoming: IncomingDocument, title: String, folder: String?) async throws -> NotebookManifest {
        let data = try await Task.detached { try Data(contentsOf: incoming.fileURL) }.value
        var manifest: NotebookManifest
        if incoming.isPDF {
            manifest = try await PDFService.importPDF(data, title: title, repository: repository)
        } else { manifest = try await repository.importArchive(data) }
        try await repository.rename(manifest.id, title: title, folder: folder)
        manifest = try await repository.load(manifest.id)
        await cancelImport(incoming); await reload()
        return manifest
    }
}
