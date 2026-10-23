import SwiftUI
import PencilKit
import UniformTypeIdentifiers

struct DrawingSnapshot: @unchecked Sendable { let drawing: PKDrawing }

@MainActor @Observable final class EditorViewModel {
    let repository: NotebookRepository
    var manifest: NotebookManifest
    var pageIndex = 0
    var loading = true
    var saveStatus = "Saved on this device"
    var error: String?
    var drawing = PKDrawing()
    var images: [NotebookImage] = []
    var imageBytes: [UUID: Data] = [:]
    var selectedImageID: UUID?
    var importingImage = false
    var isDrawing = false
    let preferences: EditorPreferences
    var onFocus: (() -> Void)?
    var tool: DrawingTool { get { preferences.tool } set { preferences.tool = newValue; if newValue != .image { selectedImageID = nil } } }
    var color: Color { get { preferences.color } set { preferences.color = newValue } }
    var width: Double { get { preferences.width } set { preferences.width = newValue } }
    var penStyle: PenStyle { get { preferences.penStyle } set { preferences.penStyle = newValue } }
    var scribbleToErase: Bool { get { preferences.scribbleToErase } set { preferences.scribbleToErase = newValue } }
    var scribbleIncludesHighlighter: Bool { get { preferences.scribbleIncludesHighlighter } set { preferences.scribbleIncludesHighlighter = newValue } }
    var pageScrollDirection: PageScrollDirection { get { preferences.pageScrollDirection } set { preferences.pageScrollDirection = newValue } }
    var precisionEraser: Bool { get { preferences.precisionEraser } set { preferences.precisionEraser = newValue } }
    var pencilOnly: Bool { get { preferences.pencilOnly } set { preferences.pencilOnly = newValue } }
    var zoomFactor = 1.0
    var zoomResetRevision = 0
    var canvas: PKCanvasView?
    let history = UndoManager()
    var historyRevision = 0
    private var pending: Task<Void, Never>?
    private(set) var loadTask: Task<Void, Never>?
    private(set) var navigationTask: Task<Void, Never>?
    private var revision = 0
    private var failedInk = false
    private var failedImages = false
    var page: NotebookPage { manifest.pages[pageIndex] }
    var selectedImage: NotebookImage? { images.first { $0.id == selectedImageID } }
    var canUndo: Bool { _ = historyRevision; return history.canUndo || (canvas.map { $0.drawing != drawing } ?? false) }
    var canRedo: Bool { _ = historyRevision; return history.canRedo }
    private struct Snapshot { var drawing: PKDrawing; var images: [NotebookImage] }
    private var snapshot: Snapshot { Snapshot(drawing: drawing, images: images) }

    init(manifest: NotebookManifest, repository: NotebookRepository, preferences: EditorPreferences = EditorPreferences()) {
        self.manifest = manifest; self.repository = repository; self.preferences = preferences
        history.groupsByEvent = false; history.levelsOfUndo = 80

    }
    func loadPage() {
        loading = true; selectedImageID = nil
        let pageID = page.id, id = manifest.id
        loadTask?.cancel()
        loadTask = Task {
            do {
                let latest = try await repository.load(id)
                guard !Task.isCancelled else { return }
                guard let index = latest.pages.firstIndex(where: { $0.id == pageID }) else { throw DocumentError.invalidManifest }
                manifest = latest; pageIndex = index
                let page = latest.pages[index]
                let bytes = try await repository.drawing(notebook: id, page: page)
                let value = try await Task.detached(priority: .userInitiated) {
                    DrawingSnapshot(drawing: try bytes.map(PKDrawing.init(data:)) ?? PKDrawing())
                }.value
                var assets: [UUID: Data] = [:]
                for image in page.imageItems { assets[image.id] = try await repository.imageData(notebook: id, image: image) }
                guard !Task.isCancelled else { return }
                drawing = value.drawing; images = page.imageItems; imageBytes = assets
                history.removeAllActions(); historyRevision += 1
                failedInk = false; failedImages = false; error = nil; loading = false
                saveStatus = "Saved on this device"
            } catch { self.error = error.localizedDescription; loading = true }
        }
    }
    private func remember(_ value: Snapshot, name: String) {
        let opensGroup = history.groupingLevel == 0
        if opensGroup { history.beginUndoGrouping() }
        history.registerUndo(withTarget: self) { model in model.restore(value, name: name) }
        history.setActionName(name)
        if opensGroup { history.endUndoGrouping() }
        historyRevision += 1
    }
    private func restore(_ value: Snapshot, name: String) {
        guard !loading else { return }
        remember(snapshot, name: name)
        drawing = value.drawing; images = value.images; selectedImageID = nil
        if let canvas = canvas as? PaperlyCanvasView { canvas.setDrawingSilently(value.drawing) }
        else { canvas?.drawing = value.drawing }
        changed(value.drawing, recordHistory: false)
        queueImages(images)
    }
    func capturePendingCanvasChange() {
        (canvas as? PaperlyCanvasView)?.cancelPendingChange?()
        if let canvas, canvas.drawing != drawing { changed(canvas.drawing) }
    }
    func undo() {
        guard !loading, !importingImage else { return }
        capturePendingCanvasChange(); history.undo(); historyRevision += 1
    }
    func redo() {
        guard !loading, !importingImage else { return }
        capturePendingCanvasChange(); history.redo(); historyRevision += 1
    }
    func changed(_ value: PKDrawing, recordHistory: Bool = true, action: String = "Ink") {
        guard !loading else { return }
        if recordHistory, value != drawing { remember(snapshot, name: action) }
        drawing = value
        revision += 1
        let ticket = revision, pageID = page.id, id = manifest.id
        let frozen = DrawingSnapshot(drawing: value)
        let predecessor = pending
        saveStatus = "Saving locally…"
        pending = Task {
            await predecessor?.value
            do {
                let bytes = await Task.detached(priority: .userInitiated) { frozen.drawing.dataRepresentation() }.value
                manifest = try await repository.saveDrawing(bytes, notebook: id, page: pageID)
                failedInk = false; saved(ticket)
                await refreshThumbnail(ticket, notebook: id, pageID: pageID)
            } catch { failedInk = true; failed(error) }
        }
    }
    /// Runs within the serialized save chain; an older revision must not replace a newer preview.
    private func refreshThumbnail(_ ticket: Int, notebook: UUID, pageID: UUID) async {
        guard ticket == revision, page.id == pageID else { return }
        let frozen = DrawingSnapshot(drawing: drawing)
        let page = page, images = images, assets = imageBytes
        let png = await Task.detached(priority: .utility) {
            PageThumbnailRenderer.png(drawing: frozen.drawing, page: page, images: images, imageBytes: assets)
        }.value
        guard let png else { return }
        guard ticket == revision, page.id == pageID else { return }
        // The next save awaits this task, so any newer preview always commits after this one.
        try? await repository.thumbnail(notebook, page: pageID, data: png)
    }

    private func saved(_ ticket: Int) {
        if !failedInk && !failedImages {
            error = nil
            if ticket == revision { saveStatus = "Saved on this device" }
        }
    }
    private func failed(_ failure: Error) {
        error = failure.localizedDescription; saveStatus = "Could not save — retry before closing"
    }
    private func queueImages(_ value: [NotebookImage]) {
        revision += 1
        let ticket = revision, id = manifest.id, pageID = page.id
        let assets = value.reduce(into: [String: Data]()) { result, item in result[item.assetPath] = imageBytes[item.id] }
        let predecessor = pending
        saveStatus = "Saving locally…"
        pending = Task {
            await predecessor?.value
            do {
                manifest = try await repository.saveImages(value, assets: assets, notebook: id, page: pageID)
                failedImages = false; saved(ticket)
                await refreshThumbnail(ticket, notebook: id, pageID: pageID)
            } catch { failedImages = true; failed(error) }
        }
    }
    func flush() async {
        await pending?.value
        // Keep failed content in memory and retry it before navigation, export or backgrounding.
        if failedInk { changed(drawing, recordHistory: false) }
        if failedImages { queueImages(images) }
        await pending?.value
    }
    func turnPage(_ action: PagePullAction) {
        guard !loading, !importingImage else { return }
        switch action {
        case .previous: if pageIndex > 0 { navigate(-1) }
        case .next: if pageIndex + 1 < manifest.pages.count { navigate(1) }
        case .add: if pageIndex == manifest.pages.count - 1 { addPage() }
        }
    }
    func navigate(_ delta: Int) {
        guard !loading else { return }
        capturePendingCanvasChange()
        loading = true
        navigationTask = Task {
            await flush()
            guard error == nil else { loading = false; return }
            pageIndex = min(max(0, pageIndex + delta), manifest.pages.count - 1)
            loadPage()
        }
    }
    func addPage() {
        guard !loading else { return }
        capturePendingCanvasChange()
        loading = true
        navigationTask = Task {
            await flush()
            guard error == nil else { loading = false; return }
            do { manifest = try await repository.addPage(manifest.id, template: page.template); pageIndex = manifest.pages.count - 1; loadPage() }
            catch { self.error = error.localizedDescription; loading = false }
        }
    }
    func insertImage(_ data: Data, copied: NotebookImage? = nil) {
        guard !loading, !importingImage else { return }
        capturePendingCanvasChange()
        importingImage = true; tool = .image; saveStatus = "Preparing image…"
        let predecessor = pending, pageID = page.id, id = manifest.id
        let pageWidth = page.width, pageHeight = page.height
        pending = Task {
            await predecessor?.value
            defer { importingImage = false }
            do {
                let imported = try await Task.detached(priority: .userInitiated) { try ImageImportService.normalizedPNG(data) }.value
                let aspect = imported.height / imported.width
                let width = min(copied?.width ?? min(pageWidth * 0.55, 420), pageWidth * 0.9, pageHeight * 0.9 / aspect)
                let height = width * aspect
                var item = NotebookImage(assetPath: "assets/images/\(UUID()).png", x: copied.map { $0.x + 24 } ?? (pageWidth - width) / 2, y: copied.map { $0.y + 24 } ?? (pageHeight - height) / 2, width: width, height: height, rotation: copied?.rotation ?? 0)
                item = clamped(item)
                remember(snapshot, name: copied == nil ? "Insert image" : "Paste image")
                images.append(item); imageBytes[item.id] = imported.pngData; selectedImageID = item.id
                let assets = [item.assetPath: imported.pngData]
                revision += 1; let ticket = revision
                do {
                    manifest = try await repository.saveImages(images, assets: assets, notebook: id, page: pageID)
                    failedImages = false; saved(ticket)
                    await refreshThumbnail(ticket, notebook: id, pageID: pageID)
                } catch { failedImages = true; failed(error) }
            } catch { self.error = error.localizedDescription; saveStatus = "Image was not inserted" }
        }
    }
    func updateImage(_ item: NotebookImage, action: String = "Move image") {
        guard !loading, !importingImage, let index = images.firstIndex(where: { $0.id == item.id }) else { return }
        let adjusted = clamped(item)
        guard adjusted != images[index] else { return }
        remember(snapshot, name: action); images[index] = adjusted; queueImages(images)
    }
    private func clamped(_ image: NotebookImage) -> NotebookImage {
        var item = image
        let angle = item.rotation * .pi / 180
        let cosine = abs(cos(angle)), sine = abs(sin(angle))
        let boundsWidth = item.width * cosine + item.height * sine
        let boundsHeight = item.width * sine + item.height * cosine
        let fit = min(1, page.width / max(1, boundsWidth), page.height / max(1, boundsHeight))
        let centerX = item.x + item.width / 2, centerY = item.y + item.height / 2
        item.width = max(1, item.width * fit); item.height = max(1, item.height * fit)
        let halfWidth = (item.width * cosine + item.height * sine) / 2
        let halfHeight = (item.width * sine + item.height * cosine) / 2
        item.x = min(max(centerX, halfWidth), page.width - halfWidth) - item.width / 2
        item.y = min(max(centerY, halfHeight), page.height - halfHeight) - item.height / 2
        return item
    }
    func deleteSelectedImage() {
        guard !loading, !importingImage, let id = selectedImageID else { return }
        remember(snapshot, name: "Delete image"); images.removeAll { $0.id == id }; selectedImageID = nil; queueImages(images)
    }
    func copySelectedImage(cut: Bool = false) {
        guard let item = selectedImage, let bytes = imageBytes[item.id], !importingImage else { return }
        let pageID = page.id
        Task {
            do {
                let data = try await Task.detached { try ImageClipboardPayload(image: item, pngData: bytes).encoded() }.value
                UIPasteboard.general.setItems([[ImageClipboardPayload.pasteboardType: data, UTType.png.identifier: bytes]])
                if cut, page.id == pageID, selectedImageID == item.id { deleteSelectedImage() }
            } catch { self.error = error.localizedDescription }
        }
    }
    func duplicateSelectedImage() {
        guard let item = selectedImage, let data = imageBytes[item.id] else { return }; insertImage(data, copied: item)
    }
    func rotateSelectedImage() {
        guard var item = selectedImage else { return }; item.rotation = (item.rotation + 90).truncatingRemainder(dividingBy: 360); updateImage(item, action: "Rotate image")
    }
}

enum PenStyle: String, CaseIterable, Identifiable {
    case fountain = "Fountain", ball = "Ball", brush = "Brush"
    var id: String { rawValue }
    var inkType: PKInkingTool.InkType { switch self { case .fountain: .fountainPen; case .ball: .monoline; case .brush: .pen } }
    var detail: String { self == .ball ? "Consistent-width ink" : "Native pressure-responsive ink" }
}

enum DrawingTool: String, CaseIterable {
    case pen, pencil, marker, eraser, lasso, image
    var symbol: String {
        switch self { case .pen: "pencil.tip"; case .pencil: "pencil"; case .marker: "highlighter"; case .eraser: "eraser"; case .lasso: "lasso"; case .image: "photo" }
    }
    func pkTool(color: UIColor, width: Double, penStyle: PenStyle = .fountain, precisionEraser: Bool = false) -> any PKTool {
        let color = PaperInk.color(color)
        return switch self {
        case .pen: PKInkingTool(penStyle.inkType, color: color, width: min(max(width, Double(penStyle.inkType.validWidthRange.lowerBound)), Double(penStyle.inkType.validWidthRange.upperBound)))
        case .pencil: PKInkingTool(.pencil, color: color, width: width)
        case .marker: PKInkingTool(.marker, color: color.withAlphaComponent(0.4), width: width * 5)
        case .eraser: PKEraserTool(precisionEraser ? .bitmap : .vector)
        case .lasso, .image: PKLassoTool()
        }
    }
}
