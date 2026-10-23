import SwiftUI
import PDFKit

/// One document session, with independent editable page models only for the visible neighborhood.
@MainActor @Observable final class NotebookSession {
    let repository: NotebookRepository
    var manifest: NotebookManifest
    var active: EditorViewModel
    var pdf: PDFDocument?
    var error: String?
    var busy = false
    var requestedPage: UUID?
    var scrollRevision = 0
    var zoomResetRevision = 0
    var retainedPages: Set<UUID> = []
    private(set) var models: [UUID: EditorViewModel] = [:]
    var activeIndex: Int { manifest.pages.firstIndex { $0.id == active.page.id } ?? 0 }
    init(_ initial: EditorViewModel) {
        repository = initial.repository; manifest = initial.manifest; active = initial
        models[initial.page.id] = initial
        initial.onFocus = { [weak self, weak initial] in if let initial { self?.focus(initial.page.id) } }
    }
    func start() async {
        if active.loading { active.loadPage() }
        do { if let data = try await repository.pdfData(manifest.id) { pdf = PDFDocument(data: data) } }
        catch { self.error = error.localizedDescription }
    }
    func editor(for index: Int) -> EditorViewModel {
        let page = manifest.pages[index]
        if let cached = models[page.id] { return cached }
        let model = EditorViewModel(manifest: manifest, repository: repository, preferences: active.preferences)
        model.pageIndex = index
        model.onFocus = { [weak self] in self?.focus(page.id) }
        models[page.id] = model
        model.loadPage()
        return model
    }
    func focus(_ id: UUID, fromScroll: Bool = false) {
        if fromScroll && models.values.contains(where: { $0.isDrawing }) { return }
        guard active.page.id != id, let model = models[id] else { return }
        active.capturePendingCanvasChange(); active.selectedImageID = nil
        active = model
    }
    func go(to index: Int) {
        guard manifest.pages.indices.contains(index) else { return }
        let model = editor(for: index); focus(model.page.id)
        requestedPage = model.page.id; scrollRevision += 1
    }
    @discardableResult func flushAll() async -> Bool {
        let pages = Array(models.values)
        for model in pages { await model.loadTask?.value; model.capturePendingCanvasChange() }
        for model in pages {
            await model.flush()
            if let failure = model.error { error = failure; return false }
        }
        do { manifest = try await repository.load(manifest.id); error = nil; return true }
        catch { self.error = error.localizedDescription; return false }
    }
    func retry() async {
        for model in models.values where model.loading && model.error != nil { model.loadPage(); await model.loadTask?.value }
        await flushAll()
    }
    func addPage(template: PaperTemplate? = nil) {
        guard !busy else { return }; busy = true
        let selectedTemplate = template ?? active.page.template
        Task {
            defer { busy = false }
            guard await flushAll() else { return }
            do {
                manifest = try await repository.addPage(manifest.id, template: selectedTemplate)
                for model in models.values { model.manifest = manifest }
                if active.preferences.pagePresentation == .paged { zoomResetRevision += 1 }
                go(to: manifest.pages.count - 1)
            } catch { self.error = error.localizedDescription }
        }
    }
    /// Keep failed edits in memory. Never destroy a page model until its ink is safely flushed.
    func prepareRelease(_ id: UUID) async -> Bool {
        guard !retainedPages.contains(id), active.page.id != id, let model = models[id] else { return false }
        await model.loadTask?.value
        model.capturePendingCanvasChange(); await model.flush()
        if let failure = model.error { error = failure; return false }
        guard !retainedPages.contains(id), active.page.id != id else { return false }
        return true
    }
    /// Called together with removing the hosting view, with no suspension between them.
    func discardPage(_ id: UUID) -> Bool {
        guard !retainedPages.contains(id), active.page.id != id, let model = models[id] else { return false }
        model.history.removeAllActions(); models.removeValue(forKey: id); return true
    }
}

struct NotebookPageSurface: View {
    @Bindable var model: EditorViewModel
    let pdf: PDFDocument?
    var body: some View {
        ZStack {
            PaperBackground(template: model.page.template)
            if let index = model.page.pdfPage, let page = pdf?.page(at: index) { PDFPageSurface(page: page) }
            NotebookImagesView(model: model)
            WritingCanvas(model: model)
            if model.loading { ProgressView().controlSize(.large) }
        }
        .frame(width: model.page.width, height: model.page.height)
        .coordinateSpace(name: "paperPage")
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
