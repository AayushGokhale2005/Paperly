import SwiftUI
import PencilKit
import PDFKit

/// PencilKit's native lasso handles editable stroke clipboard formats. Images use
/// Paperly's versioned payload plus public PNG for interoperability.
final class PaperlyCanvasView: PKCanvasView {
    override init(frame: CGRect) { super.init(frame: frame); overrideUserInterfaceStyle = .light }
    required init?(coder: NSCoder) { super.init(coder: coder); overrideUserInterfaceStyle = .light }
    var suppressCallbacks = false
    var onPasteImage: ((Data, NotebookImage?) -> Void)?
    var onCopyImage: ((Bool) -> Void)?
    var hasSelectedImage: (() -> Bool)?
    var isEditingImages: (() -> Bool)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var cancelPendingChange: (() -> Void)?
    // The editor owns one history for ink and image edits, including scribble erase.
    // Avoid mixing PencilKit's per-stroke registrations with object undo operations.
    override var undoManager: UndoManager? { nil }
    func setDrawingSilently(_ value: PKDrawing) {
        suppressCallbacks = true; drawing = value; suppressCallbacks = false
    }
    func copySelection(cut: Bool = false) {
        if hasSelectedImage?() == true { onCopyImage?(cut) }
        else {
            let action = cut ? #selector(UIResponderStandardEditActions.cut(_:)) : #selector(UIResponderStandardEditActions.copy(_:))
            UIApplication.shared.sendAction(action, to: nil, from: self, for: nil)
        }
    }
    func pasteSelection(preferImages: Bool = false) {
        let board = UIPasteboard.general
        if let bytes = board.data(forPasteboardType: ImageClipboardPayload.pasteboardType),
           let payload = try? ImageClipboardPayload.decode(bytes) {
            onPasteImage?(payload.pngData, payload.image)
            return
        }
        // Image-mode Paste explicitly requests an image object, including PNGs from other apps.
        if preferImages, pastePublicImage(board) { return }
        // Preserve PencilKit's internal lasso responder and its editable ink formats.
        if UIApplication.shared.sendAction(#selector(UIResponderStandardEditActions.paste(_:)), to: nil, from: self, for: nil) { return }
        _ = pastePublicImage(board)
    }
    private func pastePublicImage(_ board: UIPasteboard) -> Bool {
        for type in ["public.png", "public.jpeg", "public.tiff", "public.heic"] {
            if let data = board.data(forPasteboardType: type), data.count <= NotebookManifest.maximumImageBytes {
                onPasteImage?(data, nil); return true
            }
        }
        return false
    }
    override var keyCommands: [UIKeyCommand]? {
        (super.keyCommands ?? []) + [
            UIKeyCommand(input: "z", modifierFlags: .command, action: #selector(undoPaperly)),
            UIKeyCommand(input: "z", modifierFlags: [.command, .shift], action: #selector(redoPaperly)),
            UIKeyCommand(input: "c", modifierFlags: .command, action: #selector(copyPaperly)),
            UIKeyCommand(input: "x", modifierFlags: .command, action: #selector(cutPaperly)),
            UIKeyCommand(input: "v", modifierFlags: .command, action: #selector(pastePaperly))
        ]
    }
    @objc private func copyPaperly() { copySelection() }
    @objc private func cutPaperly() { copySelection(cut: true) }
    @objc private func pastePaperly() { pasteSelection(preferImages: isEditingImages?() == true) }
    @objc private func undoPaperly() { onUndo?() }
    @objc private func redoPaperly() { onRedo?() }
}

struct WritingCanvas: UIViewRepresentable {
    @Bindable var model: EditorViewModel
    func makeUIView(context: Context) -> PaperlyCanvasView {
        let canvas = PaperlyCanvasView()
        canvas.delegate = context.coordinator
        canvas.cancelPendingChange = { [weak coordinator = context.coordinator, weak canvas] in
            if let canvas { coordinator?.commit(canvas) }
        }
        canvas.backgroundColor = .clear; canvas.isOpaque = false
        canvas.isScrollEnabled = false; canvas.drawingPolicy = .anyInput
        canvas.onPasteImage = { [weak model] bytes, copied in model?.insertImage(bytes, copied: copied) }
        canvas.onCopyImage = { [weak model] cut in model?.copySelectedImage(cut: cut) }
        canvas.isEditingImages = { [weak model] in model?.tool == .image }
        canvas.hasSelectedImage = { [weak model] in model?.tool == .image && model?.selectedImageID != nil }
        canvas.onUndo = { [weak model] in model?.undo() }
        canvas.onRedo = { [weak model] in model?.redo() }
        model.canvas = canvas
        return canvas
    }
    func updateUIView(_ canvas: PaperlyCanvasView, context: Context) {
        context.coordinator.model = model
        canvas.tool = model.tool.pkTool(color: UIColor(model.color), width: model.width, penStyle: model.penStyle, precisionEraser: model.precisionEraser)
        canvas.drawingPolicy = model.pencilOnly ? .pencilOnly : .anyInput
        if context.coordinator.loadedPage != model.page.id || context.coordinator.wasLoading {
            context.coordinator.debounce?.cancel()
            context.coordinator.completedTool = nil
            if !model.loading {
                canvas.setDrawingSilently(model.drawing)
                context.coordinator.loadedPage = model.page.id
            }
        }
        context.coordinator.wasLoading = model.loading
        canvas.isUserInteractionEnabled = !model.loading && model.tool != .image && !model.importingImage
    }
    static func dismantleUIView(_ canvas: PaperlyCanvasView, coordinator: Coordinator) {
        coordinator.debounce?.cancel()
        coordinator.model.history.removeAllActions()
        coordinator.model.isDrawing = false
        coordinator.model.canvas = nil
        canvas.delegate = nil
    }
    func makeCoordinator() -> Coordinator { Coordinator(model) }
    @MainActor final class Coordinator: NSObject, PKCanvasViewDelegate {
        var model: EditorViewModel
        var loadedPage: UUID?
        var wasLoading = true
        var debounce: Task<Void, Never>?
        var beforeTool = PKDrawing()
        var toolStarted: TimeInterval = 0
        var usingTool = false
        var completedTool: (before: PKDrawing, duration: TimeInterval, scribble: Bool, highlighter: Bool)?
        init(_ model: EditorViewModel) { self.model = model }
        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            model.isDrawing = true
            model.onFocus?()
            commit(canvasView)
            if canvasView.drawing != model.drawing { model.changed(canvasView.drawing) }
            beforeTool = canvasView.drawing
            toolStarted = ProcessInfo.processInfo.systemUptime; usingTool = true
        }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard (canvasView as? PaperlyCanvasView)?.suppressCallbacks != true, !usingTool else { return }
            debounce?.cancel()
            model.historyRevision += 1
            let pageID = model.page.id
            debounce = Task { [weak self, weak canvasView] in
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled, let self, let canvasView, self.model.page.id == pageID, !self.model.loading else { return }
                self.commit(canvasView)
            }
        }
        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            usingTool = false; model.isDrawing = false
            completedTool = (beforeTool, ProcessInfo.processInfo.systemUptime - toolStarted,
                             model.tool == .pen && model.scribbleToErase, model.scribbleIncludesHighlighter)
            // Final Pencil pressure may arrive after didEndUsingTool. Each late callback
            // restarts this short quiet period; the next tool begin commits synchronously.
            canvasViewDrawingDidChange(canvasView)
        }
        func commit(_ canvasView: PKCanvasView) {
            debounce?.cancel(); debounce = nil
            guard !model.loading else { completedTool = nil; return }
            let after = canvasView.drawing
            let completed = completedTool; completedTool = nil
            if let completed, completed.scribble,
               let replacement = StrokeEditing.scribbleReplacement(before: completed.before, after: after,
                   duration: completed.duration, includeHighlighter: completed.highlighter) {
                (canvasView as? PaperlyCanvasView)?.setDrawingSilently(replacement)
                model.changed(replacement, action: "Scribble to erase")
            } else if after != model.drawing { model.changed(after) }
        }
    }
}

struct PaperBackground: View {
    let template: PaperTemplate
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            let step: CGFloat = 32
            let ink = Color(red: 0.78, green: 0.83, blue: 0.9)
            if template == .dot {
                for x in stride(from: step, to: size.width, by: step) {
                    for y in stride(from: step, to: size.height, by: step) {
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)), with: .color(ink))
                    }
                }
            } else if template != .blank {
                var lines = Path()
                for y in stride(from: step * 2, to: size.height, by: step) { lines.move(to: CGPoint(x: 0, y: y)); lines.addLine(to: CGPoint(x: size.width, y: y)) }
                if template == .grid {
                    for x in stride(from: step, to: size.width, by: step) { lines.move(to: CGPoint(x: x, y: 0)); lines.addLine(to: CGPoint(x: x, y: size.height)) }
                }
                context.stroke(lines, with: .color(ink.opacity(0.65)), lineWidth: 0.6)
                if template == .ruled {
                    var margin = Path(); margin.move(to: CGPoint(x: 56, y: 0)); margin.addLine(to: CGPoint(x: 56, y: size.height))
                    context.stroke(margin, with: .color(.red.opacity(0.2)), lineWidth: 0.8)
                }
            }
        }
    }
}

struct PDFPageSurface: UIViewRepresentable {
    let page: PDFPage
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView(); view.isUserInteractionEnabled = false; view.autoScales = true
        view.displayMode = .singlePage; view.displayBox = .mediaBox
        view.displaysPageBreaks = false; view.pageBreakMargins = .zero; view.backgroundColor = .white
        return view
    }
    func makeCoordinator() -> PageCache { PageCache() }
    @MainActor final class PageCache { var page: PDFPage? }
    func updateUIView(_ view: PDFView, context: Context) {
        guard context.coordinator.page !== page else { return }
        context.coordinator.page = page
        let doc = PDFDocument(); if let copy = page.copy() as? PDFPage { doc.insert(copy, at: 0) }; view.document = doc
    }
}
