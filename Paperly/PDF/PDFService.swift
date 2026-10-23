import Foundation
import PDFKit
import PencilKit
import UIKit

struct PDFService {
    static func importPDF(_ data: Data, title: String, repository: NotebookRepository) async throws -> NotebookManifest {
        let pages = try await Task.detached {
            guard let document = PDFDocument(data: data), document.pageCount > 0, !document.isLocked else { throw DocumentError.invalidManifest }
            return (0..<document.pageCount).compactMap { index -> NotebookPage? in
                guard let page = document.page(at: index) else { return nil }
                let bounds = page.bounds(for: .mediaBox)
                // PDFPageSurface and PDF export both fit into the same upright page coordinates.
                let rotated = page.rotation % 180 != 0
                return NotebookPage(template: .blank, pdfPage: index, width: rotated ? bounds.height : bounds.width, height: rotated ? bounds.width : bounds.height)
            }
        }.value
        let m = try await repository.create(title: title, template: .blank, cover: "sand")
        return try await repository.attachPDF(data, to: m.id, pages: pages)
    }
    static func export(_ id: UUID, repository: NotebookRepository) async throws -> URL {
        let archive = try NotebookArchive.decode(await repository.exportData(id))
        return try await Task.detached(priority: .userInitiated) {
            let source = archive.manifest.sourcePDF.flatMap { archive.assets[$0] }.flatMap(PDFDocument.init(data:))
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Paperly-\(UUID()).pdf")
            let renderer = UIGraphicsPDFRenderer(bounds: .zero)
            try renderer.writePDF(to: url) { context in
                for page in archive.manifest.pages {
                    let rect = CGRect(x: 0, y: 0, width: page.width, height: page.height)
                    context.beginPage(withBounds: rect, pageInfo: [:])
                    let cg = context.cgContext
                    UIColor.white.setFill(); cg.fill(rect)
                    if let index = page.pdfPage, let original = source?.page(at: index), let ref = original.pageRef {
                        cg.saveGState()
                        cg.translateBy(x: 0, y: rect.height); cg.scaleBy(x: 1, y: -1)
                        cg.concatenate(ref.getDrawingTransform(.mediaBox, rect: rect, rotate: 0, preserveAspectRatio: true))
                        cg.drawPDFPage(ref); cg.restoreGState()
                    } else {
                        drawTemplate(page.template, rect: rect, context: cg)
                    }
                    for image in page.imageItems {
                        guard let bytes = archive.assets[image.assetPath], let bitmap = UIImage(data: bytes) else { continue }
                        cg.saveGState()
                        cg.translateBy(x: image.x + image.width / 2, y: image.y + image.height / 2)
                        cg.rotate(by: image.rotation * .pi / 180)
                        bitmap.draw(in: CGRect(x: -image.width / 2, y: -image.height / 2, width: image.width, height: image.height))
                        cg.restoreGState()
                    }
                    if let path = page.drawingFile, let data = archive.assets[path], let drawing = try? PKDrawing(data: data) {
                        PaperInk.image(drawing, from: rect, scale: 2).draw(in: rect)
                    }
                }
            }
            return url
        }.value
    }
    private static func drawTemplate(_ template: PaperTemplate, rect: CGRect, context: CGContext) {
        guard template != .blank else { return }
        context.setStrokeColor(UIColor(red: 0.78, green: 0.83, blue: 0.9, alpha: 0.65).cgColor); context.setLineWidth(0.6)
        for y in stride(from: CGFloat(template == .dot ? 32 : 64), to: rect.height, by: 32) {
            if template == .dot {
                for x in stride(from: CGFloat(32), to: rect.width, by: 32) { context.strokeEllipse(in: CGRect(x: x, y: y, width: 1, height: 1)) }
            } else { context.move(to: CGPoint(x: 0, y: y)); context.addLine(to: CGPoint(x: rect.width, y: y)) }
        }
        if template == .grid {
            for x in stride(from: CGFloat(32), to: rect.width, by: 32) { context.move(to: CGPoint(x: x, y: 0)); context.addLine(to: CGPoint(x: x, y: rect.height)) }
        }
        context.strokePath()
    }
}
