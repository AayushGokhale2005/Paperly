import XCTest
@testable import Paperly

@MainActor final class TrashTests: XCTestCase {
    private func withRepository(_ action: (NotebookRepository, URL) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try await action(NotebookRepository(root: root), root)
    }
    func testTrashSurvivesRelaunchExportAndRestoreWithoutLosingInk() async throws {
        try await withRepository { repo, root in
            let note = try await repo.create(title: "Ink", template: .grid, cover: "blue")
            let bytes = Data([1, 2, 3, 4])
            let saved = try await repo.saveDrawing(bytes, notebook: note.id, page: note.pages[0].id)
            try await repo.trashNotebook(note.id)
            let reopened = try NotebookRepository(root: root)
            let deleted = try await reopened.load(note.id)
            XCTAssertTrue(deleted.isTrashed)
            XCTAssertNotEqual(deleted.generation, saved.generation)
            XCTAssertEqual(SyncDecision.resolve(local: deleted.generation, base: saved.generation, remote: saved.generation), .upload)
            XCTAssertEqual(SyncDecision.resolve(local: deleted.generation, base: saved.generation, remote: UUID()), .conflict)
            let archive = try NotebookArchive.decode(await reopened.exportData(note.id))
            XCTAssertTrue(archive.manifest.isTrashed)
            XCTAssertEqual(archive.assets[deleted.pages[0].drawingFile!], bytes)
            try await reopened.restoreNotebook(note.id)
            let restored = try await reopened.load(note.id)
            let ink = try await reopened.drawing(notebook: note.id, page: restored.pages[0])
            XCTAssertFalse(restored.isTrashed)
            XCTAssertEqual(ink, bytes)
            XCTAssertNotEqual(restored.generation, deleted.generation)
        }
    }
    func testFolderRestoreOnlyRestoresItsOwnDeletionGroup() async throws {
        try await withRepository { repo, root in
            try await repo.createFolder("Classes")
            try await repo.setFolderColor("Classes", color: .pink)
            let older = try await repo.createText(title: "Previously deleted", folder: "Classes")
            let current = try await repo.createText(title: "Current", folder: "Classes")
            try await repo.trashNotebook(older.id)
            try await repo.trashFolder("Classes")
            let reopened = try NotebookRepository(root: root)
            let folders = try await reopened.folders()
            XCTAssertFalse(folders.contains("Classes"))
            let tombstone = try await reopened.folderAppearances().first { $0.name == "Classes" }!
            XCTAssertTrue(tombstone.isDeleted)
            XCTAssertEqual(tombstone.color, .pink)
            try await reopened.mergeFolderAppearances([FolderAppearance(name: "Classes")])
            let afterMerge = try await reopened.folderAppearances()
            XCTAssertEqual(afterMerge.first { $0.name == "Classes" }, tombstone)
            do { try await reopened.createFolder("Classes"); XCTFail("Must explicitly restore a trashed folder") } catch DocumentError.folderInTrash { }
            try await reopened.restoreFolder("Classes")
            let items = try await reopened.list()
            XCTAssertTrue(items.first { $0.id == older.id }!.manifest.isTrashed)
            XCTAssertFalse(items.first { $0.id == current.id }!.manifest.isTrashed)
            let styles = try await reopened.folderAppearances()
            XCTAssertFalse(styles.first { $0.name == "Classes" }!.isDeleted)
            XCTAssertEqual(styles.first { $0.name == "Classes" }!.color, .pink)
            _ = try await reopened.textDocument(current.id)
        }
    }
    func testLibrarySeparatesTrashAndSurfacesOrphans() async throws {
        try await withRepository { repo, _ in
            let root = try await repo.createText(title: "Root")
            let hidden = try await repo.createText(title: "Folder", folder: "Classes")
            let trash = try await repo.createText(title: "Deleted")
            try await repo.trashNotebook(trash.id)
            let model = LibraryViewModel(repository: repo)
            await model.reload(indexHandwriting: false)
            XCTAssertEqual(model.filtered.map(\.id), [root.id])
            model.showAll = true
            XCTAssertEqual(Set(model.filtered.map(\.id)), [root.id, hidden.id])
            model.showAll = false; model.showTrash = true
            XCTAssertEqual(model.filtered.map(\.id), [trash.id])
            try await repo.mergeFolderAppearances([FolderAppearance(name: "Classes", modifiedAt: Date(), revision: UUID(), isDeleted: true)])
            await model.reload(indexHandwriting: false)
            model.showTrash = false
            XCTAssertEqual(Set(model.filtered.map(\.id)), [root.id, hidden.id], "A concurrent active note in a deleted folder must remain reachable")
        }
    }
    func testEmptyFolderCanBeRestoredAndSingleNoteRestoreReactivatesParent() async throws {
        try await withRepository { repo, _ in
            try await repo.createFolder("Empty")
            try await repo.trashFolder("Empty")
            try await repo.restoreFolder("Empty")
            let empty = try await repo.folders()
            XCTAssertEqual(empty, ["Empty"])
            let note = try await repo.createText(title: "One", folder: "Classes")
            try await repo.trashFolder("Classes")
            try await repo.restoreNotebook(note.id)
            let folders = try await repo.folders()
            XCTAssertTrue(folders.contains("Classes"))
            let restored = try await repo.load(note.id)
            XCTAssertFalse(restored.isTrashed)
        }
    }
}
