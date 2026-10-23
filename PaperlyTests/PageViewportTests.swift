import XCTest
import SwiftUI
import PencilKit
@testable import Paperly

@MainActor final class PageViewportTests: XCTestCase {
    func testZoomKeepsPageCoordinatesAndSurvivesUpdatesThenResetsOnPageTurn() {
        let controller = PageViewportController(root: Color.white)
        let id = UUID()
        func configure(_ page: UUID, pencilOnly: Bool = false) {
            controller.configure(root: Color.white, pageID: page, pageSize: CGSize(width: 768, height: 1024),
                pageIndex: 0, pageCount: 1, direction: .vertical, pencilOnly: pencilOnly, enabled: true,
                resetRevision: 0, onZoom: { _ in }, onPage: { _ in })
            controller.view.frame = CGRect(x: 0, y: 0, width: 800, height: 1000)
            controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
        }
        configure(id)
        let scroll = controller.scrollView
        let fit = scroll.minimumZoomScale
        XCTAssertEqual(scroll.panGestureRecognizer.minimumNumberOfTouches, 2)
        scroll.setZoomScale(fit * 3, animated: false)
        let pagePoint = CGPoint(x: 150, y: 250)
        let screenPoint = controller.hosting.view.convert(pagePoint, to: controller.view)
        let recovered = controller.hosting.view.convert(screenPoint, from: controller.view)
        XCTAssertEqual(recovered.x, pagePoint.x, accuracy: 0.01)
        XCTAssertEqual(recovered.y, pagePoint.y, accuracy: 0.01)
        XCTAssertEqual(controller.hosting.view.bounds.size.width, 768, accuracy: 0.01)
        configure(id, pencilOnly: true)
        XCTAssertEqual(scroll.zoomScale, fit * 3, accuracy: 0.01, "Ink/style changes must not reset zoom")
        XCTAssertEqual(scroll.panGestureRecognizer.minimumNumberOfTouches, 1)
        configure(UUID())
        XCTAssertEqual(scroll.zoomScale, fit, accuracy: 0.01)
    }
    func testPullToAddFlushesInkAndRejectsRepeatedRequestsDuringNavigation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try NotebookRepository(root: root)
        let original = try await repository.create(title: "Page gestures", template: .grid, cover: "blue")
        let model = EditorViewModel(manifest: original, repository: repository)
        model.loadPage(); await model.loadTask?.value
        let canvas = PaperlyCanvasView(); model.canvas = canvas
        let point = PKStrokePoint(location: CGPoint(x: 150, y: 250), timeOffset: 0,
            size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        canvas.setDrawingSilently(PKDrawing(strokes: [PKStroke(ink: PKInk(.pen), path: PKStrokePath(controlPoints: [point], creationDate: Date()))]))
        model.turnPage(.add); model.turnPage(.add)
        await model.navigationTask?.value; await model.loadTask?.value
        XCTAssertNil(model.error)
        XCTAssertEqual(model.manifest.pages.count, 2)
        XCTAssertEqual(model.pageIndex, 1)
        XCTAssertEqual(model.page.template, .grid)
        let stored = try await repository.load(original.id)
        let bytes = try await repository.drawing(notebook: original.id, page: stored.pages[0])
        XCTAssertEqual(try PKDrawing(data: XCTUnwrap(bytes)).strokes.count, 1)
        // Mimic representable applying the new page before another page gesture.
        canvas.setDrawingSilently(model.drawing)
        model.turnPage(.previous)
        await model.navigationTask?.value; await model.loadTask?.value
        XCTAssertEqual(model.pageIndex, 0)
        XCTAssertEqual(model.drawing.strokes.count, 1)
        canvas.setDrawingSilently(model.drawing)
        model.turnPage(.add) // Stale end-of-document gesture must not append from an earlier page.
        XCTAssertEqual(model.manifest.pages.count, 2)
    }
}
