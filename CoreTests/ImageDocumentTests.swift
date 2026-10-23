import XCTest
@testable import PaperlyCore

final class ImageDocumentTests: XCTestCase {
    private func image(x: Double = 10) -> NotebookImage {
        NotebookImage(assetPath: "assets/images/\(UUID()).png", x: x, y: 20, width: 240, height: 160)
    }

    func testLegacyVersionOneWithoutImageKeyStillDecodes() throws {
        var manifest = NotebookManifest(title: "Legacy")
        manifest.formatVersion = 1
        let encoded = try JSONEncoder().encode(manifest)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let pages = try XCTUnwrap(object["pages"] as? [[String: Any]])
        XCTAssertNil(pages[0]["images"])
        let restored = try JSONDecoder().decode(NotebookManifest.self, from: encoded)
        try restored.validate()
        XCTAssertEqual(restored.formatVersion, 1)
        XCTAssertEqual(restored.pages[0].imageItems, [])
        XCTAssertNil(restored.pages[0].images)
    }

    func testImageRoundTripPreservesOrderPlacementAssetsAndInk() throws {
        var manifest = NotebookManifest(title: "Images")
        let first = image(), second = image(x: 300)
        manifest.pages[0].imageItems = [second, first]
        manifest.pages[0].drawingFile = "strokes/ink.drawing"
        let bytes: [String: Data] = [first.assetPath: Data([1, 2]), second.assetPath: Data([3, 4]), "strokes/ink.drawing": Data([5])]
        let archive = NotebookArchive(manifest: manifest, assets: bytes)
        let restored = try NotebookArchive.decode(archive.encoded())
        XCTAssertEqual(restored.manifest.formatVersion, 2)
        XCTAssertEqual(restored.manifest.pages[0].imageItems, [second, first])
        XCTAssertEqual(restored.assets, bytes)
        XCTAssertEqual(restored.manifest.pages[0].drawingFile, "strokes/ink.drawing")
        manifest.pages[0].imageItems = []
        XCTAssertNil(manifest.pages[0].images)
    }

    func testRejectsMissingImageAssetAndDuplicateImageIdentity() throws {
        var manifest = NotebookManifest(title: "Invalid")
        let item = image()
        manifest.pages[0].imageItems = [item]
        XCTAssertThrowsError(try NotebookArchive(manifest: manifest, assets: [:]).encoded()) { error in
            guard case DocumentError.missingAsset(let path) = error else { return XCTFail("Expected missing image") }
            XCTAssertEqual(path, item.assetPath)
        }
        manifest.pages[0].imageItems = [item, item]
        XCTAssertThrowsError(try manifest.validate())
        manifest.pages[0].imageItems = [item]
        manifest.formatVersion = 1
        XCTAssertThrowsError(try manifest.validate(), "Images must never be silently stored as v1")
    }

    func testRejectsInvalidImageGeometry() {
        let valid = image()
        var variants: [NotebookImage] = []
        for value in [Double.nan, .infinity, -.infinity] {
            var position = valid; position.x = value; variants.append(position)
            var positionY = valid; positionY.y = value; variants.append(positionY)
            var rotation = valid; rotation.rotation = value; variants.append(rotation)
            var width = valid; width.width = value; variants.append(width)
            var height = valid; height.height = value; variants.append(height)
        }
        for value in [-1.0, 0, 0.5, 20_001] {
            var width = valid; width.width = value; variants.append(width)
            var height = valid; height.height = value; variants.append(height)
        }
        for variant in variants {
            var manifest = NotebookManifest(title: "Geometry")
            manifest.pages[0].imageItems = [variant]
            XCTAssertThrowsError(try manifest.validate())
        }
    }

    func testImagePathsCannotOverwriteManifestOrStrokes() {
        for path in ["manifest.json", "strokes/a.drawing", "assets/source.pdf", "/assets/images/a.png",
                     "assets/images/../manifest.json", "assets/images/other.png", "assets/images/\(UUID()).jpg",
                     "assets/images/\(UUID()).png/child", "assets/images/\0.png"] {
            XCTAssertThrowsError(try NotebookManifest.validateImagePath(path), path)
        }
        XCTAssertNoThrow(try NotebookManifest.validateImagePath("assets/images/\(UUID().uuidString.lowercased()).png"))
    }

    func testImageByteLimitAppliesAtPortableBoundary() {
        var manifest = NotebookManifest(title: "Large image")
        let item = image()
        manifest.pages[0].imageItems = [item]
        let archive = NotebookArchive(manifest: manifest,
            assets: [item.assetPath: Data(repeating: 0, count: NotebookManifest.maximumImageBytes + 1)])
        XCTAssertThrowsError(try archive.validate())
    }
}
