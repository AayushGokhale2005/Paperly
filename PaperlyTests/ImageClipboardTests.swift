import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Paperly

final class ImageClipboardTests: XCTestCase {
    private func makeImage(width: Int = 32, height: Int = 16,
                           type: UTType = .png, orientation: Int? = nil) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.3, green: 0.6, blue: 0.9, alpha: 0.5))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let bytes = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(bytes as CFMutableData,
            type.identifier as CFString, 1, nil))
        let properties = orientation.map { [kCGImagePropertyOrientation: $0] as CFDictionary }
        CGImageDestinationAddImage(destination, image, properties)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return bytes as Data
    }

    private func payload(png: Data) -> ImageClipboardPayload {
        ImageClipboardPayload(image: NotebookImage(assetPath: "assets/images/\(UUID()).png",
            x: 35, y: 60, width: 160, height: 80, rotation: 0.2), pngData: png)
    }

    func testRoundTripPreservesImageMetadataAndPNGBytes() throws {
        let original = payload(png: try makeImage())
        let restored = try ImageClipboardPayload.decode(original.encoded())
        XCTAssertEqual(restored.formatVersion, 1)
        XCTAssertEqual(restored.image, original.image)
        XCTAssertEqual(restored.pngData, original.pngData)
        XCTAssertEqual(ImageClipboardPayload.pasteboardType, "app.paperly.image-selection")
    }

    func testRejectsMalformedVersionPathGeometryAndBytes() throws {
        let valid = payload(png: try makeImage())
        var malformed = valid; malformed.formatVersion = 42
        XCTAssertThrowsError(try ImageClipboardPayload.decode(JSONEncoder().encode(malformed)))
        malformed = valid; malformed.image.assetPath = "../manifest.json"
        XCTAssertThrowsError(try ImageClipboardPayload.decode(JSONEncoder().encode(malformed)))
        malformed = valid; malformed.image.width = 0
        XCTAssertThrowsError(try ImageClipboardPayload.decode(JSONEncoder().encode(malformed)))
        malformed = valid; malformed.pngData = Data("not a PNG".utf8)
        XCTAssertThrowsError(try ImageClipboardPayload.decode(JSONEncoder().encode(malformed)))
        malformed = valid; malformed.pngData = try makeImage(type: .jpeg)
        XCTAssertThrowsError(try ImageClipboardPayload.decode(JSONEncoder().encode(malformed)))
        XCTAssertThrowsError(try ImageClipboardPayload.decode(Data("{}".utf8)))
    }

    func testNormalizationBoundsDimensionsAndPreservesAlpha() throws {
        let normalized = try ImageImportService.normalizedPNG(makeImage(width: 3000, height: 1500))
        XCTAssertEqual(normalized.width, 2048)
        XCTAssertEqual(normalized.height, 1024)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(normalized.pngData as CFData, nil))
        XCTAssertEqual(CGImageSourceGetType(source).map { $0 as String }, UTType.png.identifier)
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertTrue([CGImageAlphaInfo.first, .last, .premultipliedFirst, .premultipliedLast].contains(image.alphaInfo))
    }

    func testNormalizationAppliesOrientation() throws {
        let normalized = try ImageImportService.normalizedPNG(makeImage(width: 40, height: 20, type: .jpeg, orientation: 6))
        XCTAssertEqual(normalized.width, 20)
        XCTAssertEqual(normalized.height, 40)
    }

    func testRejectsInvalidAndOversizedRawInput() {
        XCTAssertThrowsError(try ImageImportService.normalizedPNG(Data()))
        XCTAssertThrowsError(try ImageImportService.normalizedPNG(Data([0, 1, 2, 3])))
        XCTAssertThrowsError(try ImageImportService.normalizedPNG(Data(repeating: 0,
            count: NotebookManifest.maximumImageBytes + 1)))
    }
}
