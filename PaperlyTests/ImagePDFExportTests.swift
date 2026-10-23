import XCTest
import UIKit
import PDFKit
@testable import Paperly

@MainActor final class ImagePDFExportTests: XCTestCase {
    func testImagesExportAlongsideOriginalPDFText() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = try NotebookRepository(root: root)
        let source = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 768, height: 1024)).pdfData { context in
            context.beginPage()
            ("Original vector text" as NSString).draw(at: CGPoint(x: 30, y: 30), withAttributes: [.font: UIFont.systemFont(ofSize: 24)])
        }
        let m = try await PDFService.importPDF(source, title: "Annotated source", repository: repo)
        let bitmap = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 32)).pngData { ctx in
            UIColor.blue.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
        }
        let image = NotebookImage(assetPath: "assets/images/\(UUID()).png", x: 352, y: 496, width: 64, height: 32)
        _ = try await repo.saveImages([image], assets: [image.assetPath: bitmap], notebook: m.id, page: m.pages[0].id)
        let url = try await PDFService.export(m.id, repository: repo)
        defer { try? FileManager.default.removeItem(at: url) }
        let pdf = try XCTUnwrap(PDFDocument(url: url)), page = try XCTUnwrap(pdf.page(at: 0))
        XCTAssertTrue(page.string?.contains("Original vector text") == true)
        let thumbnail = try XCTUnwrap(page.thumbnail(of: CGSize(width: 384, height: 512), for: .mediaBox).cgImage)
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(thumbnail, in: CGRect(x: -Double(thumbnail.width) / 2, y: -Double(thumbnail.height) / 2, width: Double(thumbnail.width), height: Double(thumbnail.height)))
        XCTAssertGreaterThan(Int(pixel[2]), Int(pixel[0]) + 100, "The inserted blue image must appear in PDF output")
    }
}
