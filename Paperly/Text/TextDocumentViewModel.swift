import SwiftUI

@MainActor @Observable final class TextDocumentViewModel {
    let repository: NotebookRepository
    private(set) var manifest: NotebookManifest
    private(set) var content = TextDocument()
    private(set) var title: String
    private(set) var loading = true
    private(set) var saving = false
    private(set) var dirty = false
    var error: String?
    var focusedBlock: UUID?
    private var revision = 0
    private var debounce: Task<Void, Never>?
    private var writer: Task<Bool, Never>?
    private struct Snapshot { let title: String; let content: TextDocument }
    private var past: [Snapshot] = []
    private var future: [Snapshot] = []
    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }
    var status: String { loading ? "Opening…" : error != nil ? "Could not save — tap Retry" : dirty || saving ? "Saving locally…" : "Saved on this device" }

    init(manifest: NotebookManifest, repository: NotebookRepository) {
        self.manifest = manifest; self.repository = repository; self.title = manifest.title
    }
    func load() async {
        guard loading else { return }
        do { content = try await repository.textDocument(manifest.id); loading = false; error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func remember() {
        past.append(Snapshot(title: title, content: content))
        if past.count > 100 { past.removeFirst() }
        future.removeAll()
    }
    private func changed() {
        revision += 1; dirty = true
        debounce?.cancel()
        debounce = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            guard let self else { return }
            _ = await self.flush()
        }
    }
    func setTitle(_ value: String) { guard !loading, title != value else { return }; remember(); title = value; changed() }
    func setText(_ id: UUID, _ value: String) {
        guard !loading, let i = index(id), content.blocks[i].text != value else { return }
        remember(); content.blocks[i].text = value; changed()
    }
    func setKind(_ id: UUID, _ kind: TextBlockKind) {
        guard !loading, let i = index(id), content.blocks[i].kind != kind else { return }
        remember(); content.blocks[i].kind = kind; content.blocks[i].checked = false; changed()
    }
    func toggle(_ id: UUID) {
        guard !loading, let i = index(id) else { return }
        remember(); content.blocks[i].checked.toggle(); changed()
    }
    @discardableResult func insert(after id: UUID?, kind: TextBlockKind = .paragraph) -> UUID {
        let block = TextBlock(kind: kind)
        guard !loading else { return block.id }
        remember(); let i = id.flatMap(index).map { $0 + 1 } ?? content.blocks.count
        content.blocks.insert(block, at: i); focusedBlock = block.id; changed(); return block.id
    }
    func split(_ id: UUID, atUTF16 offset: Int, replacing length: Int = 0) {
        guard !loading, let i = index(id) else { return }
        let block = content.blocks[i]
        if block.text.isEmpty, block.kind != .paragraph { setKind(id, .paragraph); return }
        let source = block.text as NSString
        guard offset >= 0, length >= 0, offset + length <= source.length else { return }
        remember()
        content.blocks[i].text = source.substring(to: offset)
        let next = TextBlock(kind: block.kind.continuesOnReturn ? block.kind : .paragraph,
                             text: source.substring(from: offset + length))
        content.blocks.insert(next, at: i + 1); focusedBlock = next.id; changed()
    }
    func delete(_ id: UUID) {
        guard !loading, let i = index(id) else { return }
        remember()
        if content.blocks.count == 1 { content.blocks[0] = TextBlock(); focusedBlock = content.blocks[0].id }
        else { content.blocks.remove(at: i); focusedBlock = content.blocks[max(0, i - 1)].id }
        changed()
    }
    func move(_ id: UUID, by delta: Int) {
        guard !loading, let i = index(id), content.blocks.indices.contains(i + delta) else { return }
        remember(); content.blocks.swapAt(i, i + delta); changed()
    }
    func appendGeneratedNotes(_ blocks: [TextBlock]) {
        guard !loading, !blocks.isEmpty else { return }
        remember()
        if content.blocks.count == 1, content.blocks[0].kind == .paragraph, content.blocks[0].text.isEmpty {
            content.blocks = blocks
        } else {
            content.blocks.append(contentsOf: blocks)
        }
        focusedBlock = nil
        changed()
    }
    func undo() {
        guard let previous = past.popLast() else { return }
        future.append(Snapshot(title: title, content: content)); title = previous.title; content = previous.content
        focusedBlock = nil; changed()
    }
    func redo() {
        guard let next = future.popLast() else { return }
        past.append(Snapshot(title: title, content: content)); title = next.title; content = next.content
        focusedBlock = nil; changed()
    }
    private func index(_ id: UUID) -> Int? { content.blocks.firstIndex { $0.id == id } }
    /// Exactly one writer drains revisions. Edits arriving during an actor suspension are
    /// saved in the next pass, so an older completion cannot mark newer work as saved.
    func flush() async -> Bool {
        if let writer {
            let result = await writer.value
            return result && dirty ? await flush() : result
        }
        guard !loading else { return false }
        guard dirty else { return true }
        let task = Task { [self] in
            saving = true
            defer { saving = false; writer = nil }
            while dirty {
                let ticket = revision, snapshot = content, name = title
                do {
                    manifest = try await repository.saveText(snapshot, title: name, notebook: manifest.id)
                    if ticket == revision { dirty = false }
                    error = nil
                } catch { self.error = error.localizedDescription; return false }
            }
            return true
        }
        writer = task
        let result = await task.value
        return result
    }
}
