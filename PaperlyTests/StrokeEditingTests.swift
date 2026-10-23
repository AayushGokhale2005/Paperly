import XCTest
import PencilKit
@testable import Paperly

/// Tests Paperly's independent heuristic with native PencilKit paths, not a claimed
/// reconstruction of Goodnotes' private recognition algorithm. The service only accepts
/// PKDrawing values: PDF backgrounds and page images are outside its mutation boundary.
final class StrokeEditingTests: XCTestCase {
    private func stroke(_ points: [CGPoint], ink: PKInk.InkType = .monoline,
                        transform: CGAffineTransform = .identity) -> PKStroke {
        let samples = points.enumerated().map { index, point in
            PKStrokePoint(location: point,
                timeOffset: Double(index) / Double(max(1, points.count - 1)) * 0.8,
                size: CGSize(width: 3, height: 3), opacity: 1, force: 1,
                azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(ink, color: .black),
            path: PKStrokePath(controlPoints: samples, creationDate: Date()),
            transform: transform, mask: nil)
    }

    private func scribble(offset: CGPoint = .zero, ink: PKInk.InkType = .monoline,
                          transform: CGAffineTransform = .identity) -> PKStroke {
        let corners = (0..<9).map { index in
            CGPoint(x: offset.x + (index.isMultiple(of: 2) ? 100 : 200),
                    y: offset.y + 100 + CGFloat(index) * 5)
        }
        var points: [CGPoint] = []
        for index in 1..<corners.count {
            let a = corners[index - 1], b = corners[index]
            for sample in 0..<20 {
                let t = CGFloat(sample) / 20
                points.append(CGPoint(x: a.x + (b.x - a.x) * t,
                                      y: a.y + (b.y - a.y) * t))
            }
        }
        points.append(corners.last!)
        return stroke(points, ink: ink, transform: transform)
    }

    private func replacement(old: [PKStroke], gesture: PKStroke,
                             includeHighlighter: Bool = false) -> PKDrawing? {
        StrokeEditing.scribbleReplacement(before: PKDrawing(strokes: old),
            after: PKDrawing(strokes: old + [gesture]), duration: 0.8,
            includeHighlighter: includeHighlighter)
    }

    func testFastDenseScribbleRemovesRealPenTargetAndGesture() throws {
        let target = stroke([CGPoint(x: 135, y: 110), CGPoint(x: 165, y: 130)], ink: .pen)
        let result = try XCTUnwrap(replacement(old: [target], gesture: scribble()))
        XCTAssertTrue(result.strokes.isEmpty, "Both target ink and recognized erase gesture should disappear")
    }

    func testDistantInkAndHighlighterRemainInTheirOriginalOrder() throws {
        let target = stroke([CGPoint(x: 140, y: 110), CGPoint(x: 160, y: 130)])
        let distant = stroke([CGPoint(x: 400, y: 400), CGPoint(x: 450, y: 420)], ink: .pen)
        let marker = stroke([CGPoint(x: 125, y: 115), CGPoint(x: 180, y: 125)], ink: .marker)
        let result = try XCTUnwrap(replacement(old: [distant, target, marker], gesture: scribble()))
        XCTAssertEqual(result.strokes.map(\.randomSeed), [distant.randomSeed, marker.randomSeed])
        XCTAssertEqual(result.strokes.map(\.renderBounds), [distant.renderBounds, marker.renderBounds])
    }

    func testHighlighterRequiresExplicitInclusion() throws {
        let marker = stroke([CGPoint(x: 125, y: 115), CGPoint(x: 180, y: 125)], ink: .marker)
        XCTAssertNil(replacement(old: [marker], gesture: scribble()))
        let result = try XCTUnwrap(replacement(old: [marker], gesture: scribble(), includeHighlighter: true))
        XCTAssertTrue(result.strokes.isEmpty)
        // A marker drawn as the gesture itself must remain ordinary ink.
        XCTAssertNil(replacement(old: [marker], gesture: scribble(ink: .marker), includeHighlighter: true))
    }

    func testOrdinaryLineAndScribbleWithoutEligibleTargetRemainInk() {
        let target = stroke([CGPoint(x: 135, y: 110), CGPoint(x: 165, y: 130)])
        let line = stroke((0..<60).map { CGPoint(x: 100 + $0 * 2, y: 120) })
        XCTAssertNil(replacement(old: [target], gesture: line))
        let distant = stroke([CGPoint(x: 400, y: 400), CGPoint(x: 450, y: 420)])
        XCTAssertNil(replacement(old: [distant], gesture: scribble()))
        XCTAssertNil(replacement(old: [], gesture: scribble()))
    }

    func testTargetAndGestureTransformsAreAppliedToHitTesting() throws {
        let translated = CGAffineTransform(translationX: 100, y: 100)
        let target = stroke([CGPoint(x: 35, y: 10), CGPoint(x: 65, y: 30)], transform: translated)
        let result = try XCTUnwrap(replacement(old: [target], gesture: scribble()))
        XCTAssertTrue(result.strokes.isEmpty)
        let localTarget = stroke([CGPoint(x: 135, y: 110), CGPoint(x: 165, y: 130)], transform: translated)
        let shiftedGesture = scribble(transform: translated)
        let transformedResult = try XCTUnwrap(replacement(old: [localTarget], gesture: shiftedGesture))
        XCTAssertTrue(transformedResult.strokes.isEmpty)
    }

    func testUnrelatedDrawingReplacementAndSlowGestureAreRejected() {
        let target = stroke([CGPoint(x: 135, y: 110), CGPoint(x: 165, y: 130)])
        let before = PKDrawing(strokes: [target])
        XCTAssertNil(StrokeEditing.scribbleReplacement(before: before,
            after: PKDrawing(strokes: [target, scribble()]), duration: 5, includeHighlighter: false))
        XCTAssertNil(StrokeEditing.scribbleReplacement(before: before,
            after: PKDrawing(strokes: [scribble()]), duration: 0.8, includeHighlighter: false))
    }
}
