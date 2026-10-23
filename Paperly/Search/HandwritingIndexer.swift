import Foundation
import PencilKit
import UIKit
import Vision

/// Recognition is a derived, local cache. It never modifies PKDrawing or uploads page images.
actor HandwritingIndexer {
    let repository: NotebookRepository
    init(repository: NotebookRepository) { self.repository = repository }
    func refresh(_ notebooks: [NotebookSummary]) async throws {
        for item in notebooks where !item.manifest.isTrashed {
            try Task.checkCancellation()
            let m = try await repository.load(item.id)
            try await repository.pruneSearchRows(item.id)
            if m.isTextDocument {
                let fingerprint = NoteSearch.fingerprint(m, page: nil)
                if try await repository.cachedRecognition(m.id, page: nil, fingerprint: fingerprint) != nil { continue }
                let content = try await repository.textDocument(m.id)
                _ = try await repository.cacheRecognition(content.blocks.map(\.text).joined(separator: "\n"), notebook: m.id, page: nil, fingerprint: fingerprint)
            } else {
                for page in m.pages {
                    try Task.checkCancellation()
                    _ = try await indexPage(notebook: m.id, page: page.id)
                }
            }
        }
    }
    func indexPage(notebook: UUID, page id: UUID) async throws -> String {
        let m = try await repository.load(notebook)
        guard let page = m.pages.first(where: { $0.id == id }) else { throw DocumentError.invalidManifest }
        let fingerprint = NoteSearch.fingerprint(m, page: page)
        if let cached = try await repository.cachedRecognition(notebook, page: id, fingerprint: fingerprint) { return cached }
        let bytes = try await repository.drawing(notebook: notebook, page: page)
        let recognition = CancellableTextRequest()
        let worker = Task.detached(priority: .background) {
            try Task.checkCancellation()
            let result = try bytes.map { try Self.recognizeDrawing($0, page: page, request: recognition.request) } ?? ""
            try Task.checkCancellation()
            return result
        }
        let recognized = try await withTaskCancellationHandler { try await worker.value } onCancel: { recognition.request.cancel(); worker.cancel() }
        try Task.checkCancellation()
        _ = try await repository.cacheRecognition(recognized, notebook: notebook, page: id, fingerprint: fingerprint)
        return recognized
    }
    nonisolated static func recognizeDrawing(_ bytes: Data, page: NotebookPage, request: VNRecognizeTextRequest = CancellableTextRequest().request) throws -> String {
        let original = try PKDrawing(data: bytes)
        let strokes = original.strokes.filter { $0.ink.inkType != .marker }.map { stroke in
            var copy = stroke; copy.ink = PKInk(.pen, color: .black); return copy
        }
        guard !strokes.isEmpty else { return "" }
        let drawing = PKDrawing(strokes: strokes)
        let pageBounds = CGRect(x: 0, y: 0, width: page.width, height: page.height)
        let rect = drawing.bounds.insetBy(dx: -24, dy: -24).intersection(pageBounds)
        guard !rect.isNull, rect.width > 0, rect.height > 0 else { return "" }
        let scale = min(3, 2048 / max(rect.width, rect.height))
        let ink = PaperInk.image(drawing, from: rect, scale: scale)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let size = CGSize(width: ceil(rect.width * scale), height: ceil(rect.height * scale))
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size))
            ink.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let cg = image.cgImage else { return "" }
        return try recognizeImage(cg, request: request)
    }
    nonisolated static func recognizeImage(_ image: CGImage, request: VNRecognizeTextRequest = CancellableTextRequest().request) throws -> String {
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}

/// VNRequest explicitly supports cancellation while its synchronous handler is running.
final class CancellableTextRequest: @unchecked Sendable {
    let request: VNRecognizeTextRequest
    init() {
        request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.automaticallyDetectsLanguage = true
        request.minimumTextHeight = 0.005
    }
}
