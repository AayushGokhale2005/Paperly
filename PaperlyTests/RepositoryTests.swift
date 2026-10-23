import XCTest
import PencilKit
@testable import Paperly

final class RepositoryTests: XCTestCase {
    func testDrawingSurvivesRepositoryRelaunchAndPortableImport() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = try NotebookRepository(root: root)
        let m = try await repo.create(title: "Calculus", template: .grid, cover: "blue")
        let points = [CGPoint(x: 12, y: 24), CGPoint(x: 80, y: 100)].enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.1, size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let stroke = PKStroke(ink: PKInk(.pen, color: .blue), path: PKStrokePath(controlPoints: points, creationDate: Date()))
        let bytes = PKDrawing(strokes: [stroke]).dataRepresentation()
        let saved = try await repo.saveDrawing(bytes, notebook: m.id, page: m.pages[0].id)
        let reopened = try NotebookRepository(root: root)
        let loaded = try await reopened.load(m.id)
        XCTAssertEqual(loaded.generation, saved.generation)
        let recovered = try await reopened.drawing(notebook: m.id, page: loaded.pages[0])
        XCTAssertEqual(recovered, bytes)
        let exported = try await reopened.exportData(m.id)
        let copy = try await reopened.importArchive(exported)
        XCTAssertNotEqual(copy.id, m.id)
        let copyBytes = try await reopened.drawing(notebook: copy.id, page: copy.pages[0])
        XCTAssertEqual(copyBytes, bytes)
    }
    func testConflictingEditsNeverChooseOverwrite() {
        XCTAssertEqual(SyncDecision.resolve(local: UUID(), base: UUID(), remote: UUID()), .conflict)
    }
}

extension RepositoryTests {
    func testImportedArchiveReplacesCleanNotebookAndPreservesSourceAssets() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = try NotebookRepository(root: root)
        var manifest = try await repo.create(title: "First", template: .dot, cover: "sage")
        manifest.title = "Remote"; manifest.generation = UUID()
        let archive = NotebookArchive(manifest: manifest, assets: ["assets/image.png": Data([1,2,3])])
        _ = try await repo.importArchive(archive.encoded(), asCopy: false)
        let loaded = try await repo.load(manifest.id)
        XCTAssertEqual(loaded.title, "Remote")
        let exported = try NotebookArchive.decode(await repo.exportData(manifest.id))
        XCTAssertEqual(exported.assets["assets/image.png"], Data([1,2,3]))
    }
}

@MainActor final class EditorFailureTests: XCTestCase {
    func testFailedSaveKeepsLiveInkAndDoesNotSwitchPage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = try NotebookRepository(root: root)
        let first = try await repo.create(title: "Failure recovery", template: .ruled, cover: "blue")
        let m = try await repo.addPage(first.id, template: .grid)
        let vm = EditorViewModel(manifest: m, repository: repo)
        vm.loadPage(); await vm.loadTask?.value
        let point = PKStrokePoint(location: CGPoint(x: 20, y: 30), timeOffset: 0, size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        let drawing = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .blue), path: PKStrokePath(controlPoints: [point], creationDate: Date()))])
        let canvas = PKCanvasView(); canvas.drawing = drawing; vm.canvas = canvas
        let dir = await repo.directory(m.id)
        try FileManager.default.moveItem(at: dir, to: root.appendingPathComponent("preserved"))
        vm.navigate(1); await vm.navigationTask?.value
        XCTAssertNotNil(vm.error)
        XCTAssertEqual(vm.pageIndex, 0)
        XCTAssertEqual(vm.drawing.strokes.count, 1)
        XCTAssertFalse(vm.loading)
    }
    func testCorruptPageNeverBecomesEditable() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = try NotebookRepository(root: root)
        let m = try await repo.create(title: "Corrupt stroke", template: .blank, cover: "blue")
        let saved = try await repo.saveDrawing(Data([0,1,2]), notebook: m.id, page: m.pages[0].id)
        let vm = EditorViewModel(manifest: saved, repository: repo)
        vm.loadPage(); await vm.loadTask?.value
        XCTAssertTrue(vm.loading)
        XCTAssertNotNil(vm.error)
        vm.changed(PKDrawing())
        let persisted = try await repo.drawing(notebook: m.id, page: saved.pages[0])
        XCTAssertEqual(persisted, Data([0,1,2]))
    }
}

extension RepositoryTests {
    func testPortableExportThroughSymlinkUsesCorrectAssetPaths() async throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let actual = parent.appendingPathComponent("actual", isDirectory: true)
        let alias = parent.appendingPathComponent("alias", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        try FileManager.default.createDirectory(at: actual, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: actual)
        let repo = try NotebookRepository(root: alias)
        let note = try await repo.create(title: "Device path", template: .ruled, cover: "blue")
        let ink = Data([1, 2, 3, 4])
        let saved = try await repo.saveDrawing(ink, notebook: note.id, page: note.pages[0].id)
        let archive = try NotebookArchive.decode(await repo.exportData(note.id))
        XCTAssertEqual(archive.assets[saved.pages[0].drawingFile!], ink)
        XCTAssertEqual(Set(archive.assets.keys), Set([saved.pages[0].drawingFile!]))
        let copied = try await repo.importArchive(archive.encoded())
        let restoredInk = try await repo.drawing(notebook: copied.id, page: copied.pages[0])
        XCTAssertEqual(restoredInk, ink)
        let text = try await repo.createText(title: "Typing")
        let textArchive = try NotebookArchive.decode(await repo.exportData(text.id))
        XCTAssertNotNil(textArchive.assets[text.textFile!])
        XCTAssertFalse(textArchive.assets.keys.contains("manifest.json"))
    }
}

extension RepositoryTests {
    func testExportFromDeviceDocumentsDirectoryPreservesAssetNames() async throws {
        // Exercise the exact sandbox URL source used by PaperlyApp on hardware.
        // Keep the probe separate from Documents/Paperly and remove only this probe.
        let root = URL.documentsDirectory.appendingPathComponent("ArchiveProbe-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = try NotebookRepository(root: root)
        let note = try await repo.create(title: "Archive probe", template: .blank, cover: "blue")
        let ink = PKDrawing().dataRepresentation()
        let saved = try await repo.saveDrawing(ink, notebook: note.id, page: note.pages[0].id)
        let archive = try NotebookArchive.decode(await repo.exportData(note.id))
        XCTAssertEqual(archive.assets[saved.pages[0].drawingFile!], ink)
        XCTAssertEqual(Set(archive.assets.keys), Set([saved.pages[0].drawingFile!]))
        let text = try await repo.createText(title: "Text probe")
        let textArchive = try NotebookArchive.decode(await repo.exportData(text.id))
        XCTAssertNotNil(textArchive.assets[text.textFile!])
        XCTAssertEqual(Set(textArchive.assets.keys), Set([text.textFile!]))
    }
}
