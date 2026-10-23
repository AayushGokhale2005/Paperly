import XCTest
import UIKit
import PencilKit
@testable import Paperly

@MainActor final class EditorImageTests: XCTestCase {
    private func imageData() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 64, height: 32)).pngData { ctx in
            UIColor.systemBlue.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
        }
    }
    func testImageInsertionMoveUndoAndRelaunch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = try NotebookRepository(root: root)
        let initial = try await repo.create(title: "Image test", template: .blank, cover: "blue")
        let vm = EditorViewModel(manifest: initial, repository: repo)
        vm.loadPage(); await vm.loadTask?.value
        vm.insertImage(imageData()); await vm.flush()
        XCTAssertNil(vm.error); XCTAssertEqual(vm.images.count, 1)
        let original = try XCTUnwrap(vm.images.first)
        var moved = original; moved.x = 40; moved.y = 80
        vm.updateImage(moved); await vm.flush()
        XCTAssertEqual(vm.images.first?.x, 40)
        vm.undo(); await vm.flush()
        XCTAssertEqual(vm.images.first, original)
        vm.redo(); await vm.flush()
        XCTAssertEqual(vm.images.first?.x, 40)
        let stored = try await repo.load(initial.id)
        XCTAssertEqual(stored.pages[0].imageItems, vm.images)
        let archive = try NotebookArchive.decode(await repo.exportData(initial.id))
        XCTAssertNotNil(archive.assets[original.assetPath])
        let next = EditorViewModel(manifest: stored, repository: repo)
        next.loadPage(); await next.loadTask?.value
        XCTAssertEqual(next.images, vm.images)
        XCTAssertFalse(next.imageBytes.isEmpty)
    }
    func testDeletingAndUndoingImageDoesNotAffectInk() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = try NotebookRepository(root: root)
        let m = try await repo.create(title: "Mixed content", template: .ruled, cover: "blue")
        let vm = EditorViewModel(manifest: m, repository: repo)
        vm.loadPage(); await vm.loadTask?.value
        let point = PKStrokePoint(location: CGPoint(x: 10, y: 20), timeOffset: 0, size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        let ink = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen), path: PKStrokePath(controlPoints: [point], creationDate: Date()))])
        vm.changed(ink); await vm.flush()
        vm.insertImage(imageData()); await vm.flush()
        vm.deleteSelectedImage(); await vm.flush()
        XCTAssertTrue(vm.images.isEmpty); XCTAssertEqual(vm.drawing.strokes.count, 1)
        vm.undo(); await vm.flush()
        XCTAssertEqual(vm.images.count, 1); XCTAssertEqual(vm.drawing.strokes.count, 1)
    }
    func testImageAndInkRepositoryWritesPreserveEachOther() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = try NotebookRepository(root: root)
        let m = try await repo.create(title: "Interleaved", template: .blank, cover: "sage")
        let image = NotebookImage(assetPath: "assets/images/\(UUID()).png", x: 0, y: 0, width: 64, height: 32)
        _ = try await repo.saveImages([image], assets: [image.assetPath: imageData()], notebook: m.id, page: m.pages[0].id)
        let bytes = PKDrawing().dataRepresentation()
        _ = try await repo.saveDrawing(bytes, notebook: m.id, page: m.pages[0].id)
        let result = try await repo.load(m.id)
        XCTAssertEqual(result.pages[0].imageItems, [image]); XCTAssertNotNil(result.pages[0].drawingFile)
        _ = try await repo.saveImages([], notebook: m.id, page: m.pages[0].id)
        let final = try await repo.load(m.id)
        let saved = try await repo.drawing(notebook: m.id, page: final.pages[0])
        XCTAssertEqual(saved, bytes)
    }
}

extension EditorImageTests {
    func testImmediateUndoCapturesDebouncedLassoChange() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = try NotebookRepository(root: root)
        let manifest = try await repo.create(title: "Immediate undo", template: .blank, cover: "blue")
        let vm = EditorViewModel(manifest: manifest, repository: repo)
        vm.loadPage(); await vm.loadTask?.value
        let canvas = PaperlyCanvasView()
        vm.canvas = canvas
        let coordinator = WritingCanvas.Coordinator(vm)
        canvas.delegate = coordinator
        canvas.cancelPendingChange = { coordinator.debounce?.cancel() }
        let point = PKStrokePoint(location: CGPoint(x: 50, y: 60), timeOffset: 0, size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        let ink = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen), path: PKStrokePath(controlPoints: [point], creationDate: Date()))])
        canvas.setDrawingSilently(ink)
        coordinator.canvasViewDrawingDidChange(canvas)
        XCTAssertTrue(vm.canUndo)
        vm.undo()
        XCTAssertTrue(vm.drawing.strokes.isEmpty)
        XCTAssertTrue(canvas.drawing.strokes.isEmpty)
        vm.redo()
        XCTAssertEqual(vm.drawing.strokes.count, 1)
        // Simulate native cut before the 200 ms commit has run.
        canvas.setDrawingSilently(PKDrawing())
        coordinator.canvasViewDrawingDidChange(canvas)
        vm.undo()
        XCTAssertEqual(vm.drawing.strokes.count, 1)
        await vm.flush()
        let stored = try await repo.load(manifest.id)
        let storedData = try await repo.drawing(notebook: manifest.id, page: stored.pages[0])
        let data = try XCTUnwrap(storedData)
        XCTAssertEqual(try PKDrawing(data: data).strokes.count, 1)
    }
    func testSelectedImageClipboardRouting() throws {
        let canvas = PaperlyCanvasView()
        var requests: [Bool] = []
        canvas.hasSelectedImage = { true }
        canvas.onCopyImage = { requests.append($0) }
        canvas.copySelection(); canvas.copySelection(cut: true)
        XCTAssertEqual(requests, [false, true])
        let image = NotebookImage(assetPath: "assets/images/\(UUID()).png", x: 10, y: 20, width: 64, height: 32)
        let data = imageData()
        let payload = try ImageClipboardPayload(image: image, pngData: data).encoded()
        UIPasteboard.general.setItems([[ImageClipboardPayload.pasteboardType: payload, "public.png": data]])
        defer { UIPasteboard.general.items = [] }
        var pasted: NotebookImage?
        canvas.onPasteImage = { bytes, item in
            XCTAssertEqual(bytes, data); pasted = item
        }
        canvas.pasteSelection()
        XCTAssertEqual(pasted, image)
        UIPasteboard.general.setItems([["public.png": data]])
        var publicImage: Data?
        canvas.onPasteImage = { bytes, item in publicImage = bytes; XCTAssertNil(item) }
        canvas.pasteSelection(preferImages: true)
        XCTAssertEqual(publicImage, data)
    }
}
