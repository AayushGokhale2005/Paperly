import XCTest
import UIKit
@testable import Paperly

@MainActor final class WorkspaceImportTests: XCTestCase {
    func testWorkspaceShowsFoldersAndOnlyRootNotebooks() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = try NotebookRepository(root: root)
        try await repo.createFolder("Empty folder")
        let loose = try await repo.create(title: "Loose", template: .blank, cover: "blue")
        let filed = try await repo.create(title: "Lecture", template: .ruled, cover: "blue", folder: "Classes")
        let reopened = try NotebookRepository(root: root)
        let model = LibraryViewModel(repository: reopened)
        await model.reload()
        XCTAssertEqual(Set(model.folders), Set(["Classes", "Empty folder"]))
        XCTAssertEqual(model.filtered.map(\.id), [loose.id])
        model.folder = "Classes"
        XCTAssertEqual(model.filtered.map(\.id), [filed.id])
        model.folder = nil; model.showAll = true
        XCTAssertEqual(model.filtered.count, 2)
    }
    func testPDFIsStagedThenImportedIntoChosenFolder() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = try NotebookRepository(root: root)
        let source = root.appendingPathComponent("Shared lecture.pdf")
        let bytes = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 300, height: 400)).pdfData { context in
            context.beginPage(); ("Shared PDF" as NSString).draw(at: CGPoint(x: 20, y: 30), withAttributes: nil)
            context.beginPage()
        }
        try bytes.write(to: source)
        let model = LibraryViewModel(repository: repo)
        await model.importFile(source)
        XCTAssertNotNil(model.pendingImport)
        let before = try await repo.list()
        XCTAssertTrue(before.isEmpty, "Destination selection must precede notebook creation")
        try FileManager.default.removeItem(at: source)
        let restored = LibraryViewModel(repository: repo)
        await restored.restoreIncoming()
        let incoming = try XCTUnwrap(restored.pendingImport)
        let document = try await restored.finishImport(incoming, title: "Math lecture", folder: "Classes")
        XCTAssertEqual(document.title, "Math lecture")
        XCTAssertEqual(document.folder, "Classes")
        XCTAssertEqual(document.pages.count, 2)
        let originalPDF = try await repo.pdfData(document.id)
        XCTAssertEqual(originalPDF, bytes)
        XCTAssertNil(restored.pendingImport)
        XCTAssertFalse(FileManager.default.fileExists(atPath: incoming.fileURL.path))
        restored.folder = "Classes"
        XCTAssertEqual(restored.filtered.first?.id, document.id, "The imported manifest can be opened directly")
    }
}

extension WorkspaceImportTests {
    func testEmptyFoldersSurviveCrossClientMergeAndReopen() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = try NotebookRepository(root: root)
        try await repo.createFolder("Local empty")
        try await repo.mergeFolders(["Remote empty", "Local empty"])
        let reopened = try NotebookRepository(root: root)
        let model = LibraryViewModel(repository: reopened)
        await model.reload()
        XCTAssertEqual(Set(model.folders), ["Local empty", "Remote empty"])
        XCTAssertTrue(model.notebooks.isEmpty)
        do { try await repo.mergeFolders(["Valid", "bad/name"]); XCTFail("Invalid catalog accepted") } catch { }
        let remaining = try await repo.folders()
        XCTAssertFalse(remaining.contains("Valid"), "Merge validation must precede any catalog writes")
    }
}
