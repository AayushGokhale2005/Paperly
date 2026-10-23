import XCTest
import UIKit
import PencilKit
@testable import Paperly

@MainActor final class HandwritingSearchTests: XCTestCase {
    private func withRepository(_ action: (NotebookRepository, URL) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try await action(NotebookRepository(root: root), root)
    }
    func testFolderColorSurvivesReopenAndOlderSyncCannotReplaceIt() async throws {
        try await withRepository { repo, root in
            try await repo.createFolder("Classes")
            try await repo.setFolderColor("Classes", color: .purple)
            let before = try await repo.folderAppearances()
            try await repo.mergeFolderAppearances([FolderAppearance(name: "Classes"), FolderAppearance(name: "Empty")])
            let reopened = try NotebookRepository(root: root)
            let after = try await reopened.folderAppearances()
            XCTAssertEqual(after.first { $0.name == "Classes" }, before.first)
            XCTAssertEqual(after.first { $0.name == "Empty" }?.color, .blue)
            let future = FolderAppearance(name: "Classes", color: .orange, modifiedAt: Date().addingTimeInterval(3600), revision: UUID())
            try await repo.mergeFolderAppearances([future])
            try await repo.setFolderColor("Classes", color: .green)
            let final = try await repo.folderAppearances()
            XCTAssertEqual(final.first { $0.name == "Classes" }?.color, .green, "A local user choice must work despite another device's clock skew")
        }
    }
    func testSearchFindsSymbolsAndOpensMatchingPageIdentity() async throws {
        try await withRepository { repo, _ in
            let first = try await repo.create(title: "Calculus", template: .ruled, cover: "blue")
            let m = try await repo.addPage(first.id, template: .grid)
            let page = m.pages[1]
            let fingerprint = NoteSearch.fingerprint(m, page: page)
            let stored = try await repo.cacheRecognition("α ≤ x² and ∫ f(x) dx, 100% complete", notebook: m.id, page: page.id, fingerprint: fingerprint)
            XCTAssertTrue(stored)
            for query in ["alpha", "<=", "x^2", "integral", "100%", "α x²"] {
                let hits = try await repo.search(query)
                XCTAssertEqual(hits.first?.notebookID, m.id)
                XCTAssertEqual(hits.first?.pageID, page.id)
                XCTAssertEqual(hits.first?.pageNumber, 2)
            }
            let model = LibraryViewModel(repository: repo)
            await model.reload(); model.pauseIndexing(); model.query = "integral"; await model.searchNow()
            XCTAssertEqual(model.filtered.map(\.id), [m.id])
            XCTAssertEqual(model.searchHits[m.id]?.first?.pageID, page.id)
        }
    }
    func testChangedDrawingRejectsStaleResultsAndReindexDropsErasedWords() async throws {
        try await withRepository { repo, _ in
            let m = try await repo.create(title: "Revisions", template: .blank, cover: "blue")
            let page = m.pages[0], key = NoteSearch.fingerprint(m, page: m.pages[0])
            _ = try await repo.cacheRecognition("oldword", notebook: m.id, page: page.id, fingerprint: key)
            let updated = try await repo.saveDrawing(PKDrawing().dataRepresentation(), notebook: m.id, page: page.id)
            let staleWrite = try await repo.cacheRecognition("late oldword", notebook: m.id, page: page.id, fingerprint: key)
            XCTAssertFalse(staleWrite)
            let staleHits = try await repo.search("oldword"); XCTAssertTrue(staleHits.isEmpty)
            _ = try await HandwritingIndexer(repository: repo).indexPage(notebook: m.id, page: page.id)
            let hits = try await repo.search("oldword"); XCTAssertTrue(hits.isEmpty)
            XCTAssertNotEqual(NoteSearch.fingerprint(updated, page: updated.pages[0]), key)
        }
    }
    func testManualTermsExportAndSearchPreserveEditableInk() async throws {
        try await withRepository { repo, _ in
            let m = try await repo.create(title: "Symbols", template: .blank, cover: "blue")
            let bytes = PKDrawing().dataRepresentation()
            _ = try await repo.saveDrawing(bytes, notebook: m.id, page: m.pages[0].id)
            let tagged = try await repo.saveSearchTerms("infinity ∫ customname", notebook: m.id, page: m.pages[0].id)
            XCTAssertEqual(tagged.formatVersion, 4)
            let archive = try await repo.exportData(m.id)
            let copied = try await repo.importArchive(archive)
            XCTAssertEqual(copied.pages[0].searchTerms, "infinity ∫ customname")
            let ink = try await repo.drawing(notebook: copied.id, page: copied.pages[0]); XCTAssertEqual(ink, bytes)
            _ = try await HandwritingIndexer(repository: repo).indexPage(notebook: copied.id, page: copied.pages[0].id)
            let hits = try await repo.search("infinity"); XCTAssertEqual(hits.first?.notebookID, copied.id)
        }
    }
    func testTypedDocumentBodyIsSearchableAndInvalidatedOnEdit() async throws {
        try await withRepository { repo, _ in
            let m = try await repo.createText(title: "Plan")
            _ = try await repo.saveText(TextDocument(blocks: [.init(text: "A hidden milestone")]), title: "Plan", notebook: m.id)
            let indexer = HandwritingIndexer(repository: repo)
            try await indexer.refresh(repo.list())
            let hits = try await repo.search("milestone"); XCTAssertEqual(hits.first?.notebookID, m.id); XCTAssertNil(hits.first?.pageID)
            _ = try await repo.saveText(TextDocument(blocks: [.init(text: "A new target")]), title: "Plan", notebook: m.id)
            let oldHits = try await repo.search("milestone"); XCTAssertTrue(oldHits.isEmpty)
            try await indexer.refresh(repo.list())
            let newHits = try await repo.search("target"); XCTAssertEqual(newHits.first?.notebookID, m.id)
        }
    }
    func testVisionRecognitionControlImageRunsLocally() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 180)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1000, height: 180))
            ("PAPERLY SEARCH 314" as NSString).draw(at: CGPoint(x: 40, y: 50), withAttributes: [.font: UIFont.systemFont(ofSize: 64), .foregroundColor: UIColor.black])
        }
        let bytes = try XCTUnwrap(image.pngData())
        let recognized = try await Task.detached(priority: .background) {
            guard let cg = UIImage(data: bytes)?.cgImage else { throw DocumentError.invalidManifest }
            return try HandwritingIndexer.recognizeImage(cg)
        }.value
        XCTAssertTrue(recognized.uppercased().contains("PAPERLY"), recognized)
        XCTAssertTrue(recognized.contains("314"), recognized)
    }
}
