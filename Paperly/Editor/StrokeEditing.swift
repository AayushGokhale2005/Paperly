import Foundation
import PencilKit

/// Independent geometric behavior; not Goodnotes' private gesture algorithm.
enum StrokeEditing {
    static func scribbleReplacement(before: PKDrawing, after: PKDrawing, duration: TimeInterval, includeHighlighter: Bool) -> PKDrawing? {
        guard after.strokes.count == before.strokes.count + 1, let gesture = after.strokes.last,
              isPen(gesture.ink.inkType),
              Array(after.strokes.dropLast()).elementsEqual(before.strokes, by: { $0.randomSeed == $1.randomSeed && $0.renderBounds == $1.renderBounds }) else { return nil }
        let points = gesture.path.interpolatedPoints(by: .distance(3)).prefix(4096).map {
            let location = $0.location.applying(gesture.transform)
            return ScribblePoint(x: location.x, y: location.y)
        }
        guard let region = ScribbleGestureDetector.region(for: points, duration: duration) else { return nil }
        let rect = CGRect(x: region.minX - 4, y: region.minY - 4, width: region.width + 8, height: region.height + 8)
        let remaining = before.strokes.filter { stroke in
            guard isPen(stroke.ink.inkType) || (includeHighlighter && stroke.ink.inkType == .marker), stroke.renderBounds.intersects(rect) else { return true }
            // Hit-test actual centerlines, not merely overlapping bounding boxes.
            return !stroke.path.interpolatedPoints(by: .distance(4)).prefix(8192).contains { point in
                let location = point.location.applying(stroke.transform)
                return region.contains(ScribblePoint(x: location.x, y: location.y), tolerance: 4)
            }
        }
        guard remaining.count < before.strokes.count else { return nil }
        return PKDrawing(strokes: remaining)
    }
    private static func isPen(_ type: PKInk.InkType) -> Bool { type == .pen || type == .fountainPen || type == .monoline }
}
