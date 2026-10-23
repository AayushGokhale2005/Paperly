import XCTest
import UIKit
import PencilKit
@testable import Paperly

@MainActor final class PageThumbnailTests: XCTestCase {
    func testImageOnlyThumbnailHasVisiblePixelsAndTransparentPageMargins() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1; format.opaque = false
        let source = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10), format: format).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
        let item = NotebookImage(assetPath: "assets/images/\(UUID()).png",
            x: 25, y: 25, width: 50, height: 50)
        let page = NotebookPage(width: 100, height: 100, images: [item])
        let png = try XCTUnwrap(PageThumbnailRenderer.png(drawing: PKDrawing(), page: page,
            images: [item], imageBytes: [item.id: try XCTUnwrap(source.pngData())]))
        let thumbnail = try XCTUnwrap(UIImage(data: png)?.cgImage)
        XCTAssertEqual(thumbnail.width, 20)
        XCTAssertEqual(thumbnail.height, 20)
        var rgba = [UInt8](repeating: 0, count: 20 * 20 * 4)
        try rgba.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 20, height: 20,
                bitsPerComponent: 8, bytesPerRow: 80, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(thumbnail, in: CGRect(x: 0, y: 0, width: 20, height: 20))
        }
        let center = (10 * 20 + 10) * 4
        XCTAssertGreaterThan(rgba[center], 200, "Inserted image must appear even when there is no ink")
        XCTAssertGreaterThan(rgba[center + 3], 200)
        XCTAssertEqual(rgba[3], 0, "Page margin should remain transparent")
    }
}
