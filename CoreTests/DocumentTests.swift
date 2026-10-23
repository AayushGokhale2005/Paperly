import XCTest
@testable import PaperlyCore
final class DocumentTests: XCTestCase {
    func testRoundTripPreservesIdentityOrderTemplatesAndAssets() throws {
        var m = NotebookManifest(title: "Calculus")
        m.pages[0].drawingFile = "strokes/first.drawing"
        m.pages.append(NotebookPage(template: .grid)); m.sourcePDF = "assets/source.pdf"
        let a = NotebookArchive(manifest: m, assets: ["strokes/first.drawing": Data([1,2,3]), "assets/source.pdf": Data([4,5])])
        let restored = try NotebookArchive.decode(a.encoded())
        XCTAssertEqual(restored.manifest, m); XCTAssertEqual(restored.assets, a.assets)
    }
    func testRejectsFutureVersionsAndTraversalAndMissingStrokes() throws {
        var m = NotebookManifest(title: "Test"); m.formatVersion = 999
        XCTAssertThrowsError(try m.validate()); m.formatVersion = 1
        m.pages[0].drawingFile = "../outside"; XCTAssertThrowsError(try m.validate())
        m.pages[0].drawingFile = "strokes/missing.drawing"
        XCTAssertThrowsError(try NotebookArchive(manifest: m, assets: [:]).encoded())
    }
    func testRejectsDuplicatePagesAndInvalidSize() throws {
        var m = NotebookManifest(title: "Test"); m.pages.append(m.pages[0])
        XCTAssertThrowsError(try m.validate()); m.pages.removeLast(); m.pages[0].width = -1
        XCTAssertThrowsError(try m.validate())
    }
    func testConflictMatrix() {
        let base = UUID(), local = UUID(), remote = UUID()
        XCTAssertEqual(SyncDecision.resolve(local: local, base: nil, remote: nil), .upload)
        XCTAssertEqual(SyncDecision.resolve(local: base, base: base, remote: base), .unchanged)
        XCTAssertEqual(SyncDecision.resolve(local: local, base: base, remote: base), .upload)
        XCTAssertEqual(SyncDecision.resolve(local: base, base: base, remote: remote), .download)
        XCTAssertEqual(SyncDecision.resolve(local: local, base: base, remote: remote), .conflict)
        XCTAssertEqual(SyncDecision.resolve(local: local, base: base, remote: nil), .conflict)
        XCTAssertEqual(SyncDecision.resolve(local: local, base: nil, remote: remote), .conflict)
    }
    func testRemoteBranchesRemainSeparateHeads() {
        let id = UUID(), a = UUID(), b = UUID(), c = UUID()
        func snap(_ generation: UUID, _ parent: UUID?) -> RemoteSnapshot {
            var props = ["notebookID": id.uuidString, "generation": generation.uuidString]
            props["parent"] = parent?.uuidString
            return RemoteSnapshot(id: generation.uuidString, name: nil, version: "1", appProperties: props)
        }
        let history = [snap(a, nil), snap(b, a), snap(c, a)]
        XCTAssertEqual(Set(RemoteSnapshot.heads(history).compactMap(\.generation)), [b,c])
    }
}

extension DocumentTests {
    func testDuplicateGenerationsAreNotConflictsAndResolutionPreservesAncestors() {
        let base = UUID(), a = UUID(), b = UUID(), merged = UUID()
        let original = RemoteSnapshot(id: "base", name: nil, version: "1", appProperties: ["generation": base.uuidString])
        let left = RemoteSnapshot(id: "left", name: nil, version: "1", appProperties: ["generation": a.uuidString, "parent": base.uuidString])
        var duplicate = left; duplicate.id = "duplicate"
        let right = RemoteSnapshot(id: "right", name: nil, version: "1", appProperties: ["generation": b.uuidString, "parent": base.uuidString])
        XCTAssertEqual(RemoteSnapshot.heads([original, left, duplicate]).count, 1)
        let resolved = RemoteSnapshot(id: "merged", name: nil, version: "1", appProperties: ["generation": merged.uuidString, "ancestor_" + a.uuidString: "1", "ancestor_" + b.uuidString: "1"])
        XCTAssertEqual(RemoteSnapshot.heads([original, left, right, resolved]).compactMap(\.generation), [merged])
    }
}
