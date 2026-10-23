import Foundation

public struct ScribblePoint: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct ScribbleRegion: Equatable, Sendable {
    public var minX: Double
    public var minY: Double
    public var maxX: Double
    public var maxY: Double
    public var width: Double { maxX - minX }
    public var height: Double { maxY - minY }

    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    public func contains(_ point: ScribblePoint, tolerance: Double = 0) -> Bool {
        guard point.x.isFinite, point.y.isFinite, tolerance.isFinite,
              tolerance >= 0 else { return false }
        return point.x >= minX - tolerance && point.x <= maxX + tolerance
            && point.y >= minY - tolerance && point.y <= maxY + tolerance
    }
}

/// An independently designed geometric heuristic, not a recovered Goodnotes algorithm.
/// Coordinates are page points. It deliberately favors missed gestures over erasing writing.
/// Callers must separately check existing eligible ink and make deletion undoable.
public enum ScribbleGestureDetector {
    public static func region(for points: [ScribblePoint], duration: Double) -> ScribbleRegion? {
        guard (6...4096).contains(points.count), duration.isFinite,
              duration >= 0.08, duration <= 2.5,
              points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 1e7 && abs($0.y) <= 1e7 })
        else { return nil }

        let region = ScribbleRegion(
            minX: points.map(\.x).min()!, minY: points.map(\.y).min()!,
            maxX: points.map(\.x).max()!, maxY: points.map(\.y).max()!
        )
        let diagonal = hypot(region.width, region.height)
        guard diagonal >= 20, diagonal <= 500 else { return nil }

        // Centering first keeps covariance stable even on pages far from the origin.
        let meanX = points.reduce(0) { $0 + $1.x } / Double(points.count)
        let meanY = points.reduce(0) { $0 + $1.y } / Double(points.count)
        var xx = 0.0, yy = 0.0, xy = 0.0
        for point in points {
            let x = point.x - meanX, y = point.y - meanY
            xx += x * x; yy += y * y; xy += x * y
        }
        let angle = 0.5 * atan2(2 * xy, xx - yy)
        let axisX = cos(angle), axisY = sin(angle)
        let projected = points.map { ($0.x - meanX) * axisX + ($0.y - meanY) * axisY }
        let transverse = points.map { -($0.x - meanX) * axisY + ($0.y - meanY) * axisX }
        let span = projected.max()! - projected.min()!
        let breadth = transverse.max()! - transverse.min()!
        guard span >= 20, breadth <= span * 0.85 else { return nil }

        // Simplification removes sample jitter without turning a smooth wave into a sharp zigzag.
        let simplified = simplify(points, tolerance: max(1.5, span * 0.02))
        guard simplified.count >= 6 else { return nil }
        var length = 0.0
        for index in 1..<simplified.count {
            length += distance(simplified[index - 1], simplified[index])
        }
        guard length / span >= 4.5, length / span <= 24,
              length / duration >= 100, length / duration <= 10_000 else { return nil }

        // Each qualifying corner must reverse across a substantial fraction of the span
        // and turn at least 120 degrees. Smooth sine waves and loops fail the sharpness gate.
        var reversals = 0
        for index in 1..<(simplified.count - 1) {
            let a = simplified[index - 1], b = simplified[index], c = simplified[index + 1]
            let incomingX = b.x - a.x, incomingY = b.y - a.y
            let outgoingX = c.x - b.x, outgoingY = c.y - b.y
            let incomingProjection = incomingX * axisX + incomingY * axisY
            let outgoingProjection = outgoingX * axisX + outgoingY * axisY
            guard incomingProjection * outgoingProjection < 0,
                  abs(incomingProjection) >= span * 0.3,
                  abs(outgoingProjection) >= span * 0.3 else { continue }
            let denominator = hypot(incomingX, incomingY) * hypot(outgoingX, outgoingY)
            if denominator > 0,
               (incomingX * outgoingX + incomingY * outgoingY) / denominator <= -0.5 {
                reversals += 1
            }
        }
        return reversals >= 4 ? region : nil
    }

    private static func distance(_ a: ScribblePoint, _ b: ScribblePoint) -> Double {
        hypot(b.x - a.x, b.y - a.y)
    }

    /// Iterative Ramer–Douglas–Peucker; input is capped to bound worst-case work.
    private static func simplify(_ points: [ScribblePoint], tolerance: Double) -> [ScribblePoint] {
        // Preserve sharp direction reversals before RDP: ordinary RDP otherwise
        // collapses repeated collinear backtracking into one segment.
        var anchors = [0]
        for index in 1..<(points.count - 1) {
            let a = points[index - 1], b = points[index], c = points[index + 1]
            let dx1 = b.x - a.x, dy1 = b.y - a.y
            let dx2 = c.x - b.x, dy2 = c.y - b.y
            let length1 = hypot(dx1, dy1), length2 = hypot(dx2, dy2)
            if length1 > 0, length2 > 0,
               (dx1 * dx2 + dy1 * dy2) / (length1 * length2) <= -0.5 {
                anchors.append(index)
            }
        }
        anchors.append(points.count - 1)
        var retained = Set(anchors)
        var pending = zip(anchors, anchors.dropFirst()).map { ($0.0, $0.1) }
        while let (start, end) = pending.popLast() {
            guard end > start + 1 else { continue }
            let a = points[start], b = points[end]
            let dx = b.x - a.x, dy = b.y - a.y
            let squaredLength = dx * dx + dy * dy
            var furthest = tolerance, selected: Int?
            for index in (start + 1)..<end {
                let point = points[index]
                let t = squaredLength == 0 ? 0 : max(0, min(1,
                    ((point.x - a.x) * dx + (point.y - a.y) * dy) / squaredLength))
                let deviation = hypot(point.x - a.x - t * dx, point.y - a.y - t * dy)
                if deviation > furthest { furthest = deviation; selected = index }
            }
            if let selected {
                retained.insert(selected)
                pending.append((start, selected))
                pending.append((selected, end))
            }
        }
        return retained.sorted().map { points[$0] }
    }
}
