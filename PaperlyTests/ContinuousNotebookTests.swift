import XCTest
import SwiftUI
import PencilKit
@testable import Paperly

@MainActor final class ContinuousNotebookTests: XCTestCase {
    func testContinuousDocumentIsTallerThanViewportAndLoadsOnlyNearbyPages() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = try NotebookRepository(root: root)
        var manifest = NotebookManifest(title: "Continuous", template: .ruled, cover: "blue")
        manifest.pages = (0..<30).map { _ in NotebookPage(template: .ruled) }
        manifest = try await repo.importArchive(NotebookArchive(manifest: manifest, assets: [:]).encoded())
        let session = NotebookSession(EditorViewModel(manifest: manifest, repository: repo))
        await session.start()
        let controller = ContinuousNotebookController(session: session)
        controller.configure(direction: .vertical, oneFingerPan: false, resetRevision: 0, scrollRevision: 0, pages: manifest.pages, pdfReady: false)
        controller.view.frame = CGRect(x: 0, y: 0, width: 800, height: 900)
        controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
        XCTAssertGreaterThan(controller.scroll.contentSize.height, 20_000)
        XCTAssertLessThan(session.models.count, 6)
        XCTAssertEqual(controller.scroll.panGestureRecognizer.minimumNumberOfTouches, 2)
        let fit = controller.scroll.minimumZoomScale
        controller.scroll.setZoomScale(fit * 2, animated: false)
        controller.configure(direction: .vertical, oneFingerPan: true, resetRevision: 0, scrollRevision: 0, pages: manifest.pages, pdfReady: false)
        controller.view.layoutIfNeeded()
        XCTAssertEqual(controller.scroll.zoomScale, fit * 2, accuracy: 0.01)
        XCTAssertEqual(controller.scroll.panGestureRecognizer.minimumNumberOfTouches, 1)
        let adjacent = session.editor(for: 1)
        session.focus(adjacent.page.id)
        controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
        await Task.yield()
        XCTAssertEqual(session.active.page.id, adjacent.page.id, "A toolbar/layout update must not move Undo away from the last edited page")
        await session.flushAll()
    }
    func testAdjacentPagesShareToolsButKeepIndependentInkAndUndo() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = try NotebookRepository(root: root)
        let first = try await repo.create(title: "Adjacent pages", template: .grid, cover: "blue")
        let manifest = try await repo.addPage(first.id, template: .ruled)
        let session = NotebookSession(EditorViewModel(manifest: manifest, repository: repo))
        await session.start(); await session.active.loadTask?.value
        let a = session.editor(for: 0), b = session.editor(for: 1)
        await b.loadTask?.value
        a.color = .black; XCTAssertTrue(a.preferences === b.preferences)
        let point = PKStrokePoint(location: CGPoint(x: 50, y: 70), timeOffset: 0, size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        let ink = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: [point], creationDate: Date()))])
        a.changed(ink); b.changed(ink)
        let saved0 = await session.flushAll(); XCTAssertTrue(saved0)
        session.focus(b.page.id); b.undo()
        let saved1 = await session.flushAll(); XCTAssertTrue(saved1)
        let stored = try await repo.load(manifest.id)
        let bytesA = try await repo.drawing(notebook: stored.id, page: stored.pages[0])
        let bytesB = try await repo.drawing(notebook: stored.id, page: stored.pages[1])
        XCTAssertEqual(try PKDrawing(data: XCTUnwrap(bytesA)).strokes.count, 1)
        XCTAssertEqual(try PKDrawing(data: XCTUnwrap(bytesB)).strokes.count, 0)
    }
    func testEvictedPageReloadsLatestImageMetadata() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = try NotebookRepository(root: root)
        let first = try await repo.create(title: "Lazy assets", template: .blank, cover: "blue")
        let manifest = try await repo.addPage(first.id, template: .blank)
        let session = NotebookSession(EditorViewModel(manifest: manifest, repository: repo))
        await session.start(); await session.active.loadTask?.value
        let firstEditor = session.active
        let bytes = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).pngData { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        }
        firstEditor.insertImage(bytes); await firstEditor.flush()
        let next = session.editor(for: 1); await next.loadTask?.value
        session.focus(next.page.id); session.retainedPages = [next.page.id]
        let released = await session.prepareRelease(firstEditor.page.id)
        XCTAssertTrue(released)
        XCTAssertTrue(session.discardPage(firstEditor.page.id))
        let reloaded = session.editor(for: 0); await reloaded.loadTask?.value
        XCTAssertNil(reloaded.error)
        XCTAssertEqual(reloaded.images.count, 1)
        XCTAssertFalse(reloaded.imageBytes.isEmpty)
        await session.flushAll()
    }

}

extension ContinuousNotebookTests {
    func testPagedModeFitsOneWholePageAndSwipeSnapsToNext() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = try NotebookRepository(root: root)
        let first = try await repo.create(title: "Paging", template: .ruled, cover: "blue")
        let manifest = try await repo.addPage(first.id, template: .grid)
        let session = NotebookSession(EditorViewModel(manifest: manifest, repository: repo))
        await session.start(); await session.active.loadTask?.value
        let controller = ContinuousNotebookController(session: session)
        controller.configure(direction: .vertical, oneFingerPan: false, resetRevision: 0, scrollRevision: 0, pages: manifest.pages, pdfReady: false, paged: true)
        controller.view.frame = CGRect(x: 0, y: 0, width: 800, height: 900)
        controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
        XCTAssertTrue(controller.scroll.isPagingEnabled)
        XCTAssertEqual(controller.scroll.contentSize.height, 1800, accuracy: 0.1)
        XCTAssertEqual(controller.scroll.contentInset.top, 0, accuracy: 0.1)
        XCTAssertLessThanOrEqual(1024 * controller.scroll.zoomScale, 868)
        var target = CGPoint(x: 0, y: 1250)
        controller.scrollViewWillBeginDragging(controller.scroll)
        controller.scrollViewWillEndDragging(controller.scroll, withVelocity: CGPoint(x: 0, y: 1), targetContentOffset: &target)
        XCTAssertEqual(target.y, 900, accuracy: 0.1)
        session.go(to: 1)
        controller.configure(direction: .vertical, oneFingerPan: false, resetRevision: 0, scrollRevision: session.scrollRevision, pages: manifest.pages, pdfReady: false, paged: true)
        controller.view.layoutIfNeeded()
        XCTAssertEqual(controller.scroll.contentOffset.y, 900, accuracy: 0.1)
        controller.scroll.setZoomScale(controller.scroll.minimumZoomScale * 2, animated: false)
        XCTAssertFalse(controller.scroll.isPagingEnabled, "Zoomed pages must pan freely without snapping while writing")
        await session.flushAll()
    }
    func testAddingPageActivatesItAndRequestsFreshFit() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = try NotebookRepository(root: root)
        let manifest = try await repo.create(title: "New page", template: .dot, cover: "blue")
        let session = NotebookSession(EditorViewModel(manifest: manifest, repository: repo))
        await session.start(); await session.active.loadTask?.value
        session.active.preferences.pagePresentation = .paged
        let oldReset = session.zoomResetRevision
        session.addPage()
        for _ in 0..<200 where session.busy { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(session.busy); XCTAssertNil(session.error)
        XCTAssertEqual(session.manifest.pages.count, 2)
        XCTAssertEqual(session.activeIndex, 1)
        XCTAssertEqual(session.requestedPage, session.manifest.pages.last?.id)
        XCTAssertGreaterThan(session.zoomResetRevision, oldReset)
        XCTAssertEqual(session.active.page.template, .dot)
        await session.flushAll()
    }
}
