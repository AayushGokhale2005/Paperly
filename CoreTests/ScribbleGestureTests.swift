import XCTest
@testable import PaperlyCore

final class ScribbleGestureTests: XCTestCase {
    private let zigzag = (0..<9).map { ScribblePoint(x: $0.isMultiple(of: 2) ? 0 : 100, y: Double($0) * 5) }

    func testDenseZigzagAndHorizontalRetracing() throws {
        let bounds = try XCTUnwrap(ScribbleGestureDetector.region(for: zigzag, duration: 0.8))
        XCTAssertEqual(bounds.width, 100)
        XCTAssertEqual(bounds.height, 40)
        XCTAssertTrue(bounds.contains(ScribblePoint(x: 50, y: 20)))
        XCTAssertTrue(bounds.contains(ScribblePoint(x: -2, y: 20), tolerance: 2))
        XCTAssertFalse(bounds.contains(ScribblePoint(x: -3, y: 20), tolerance: 2))
        let horizontal = zigzag.map { ScribblePoint(x: $0.x, y: 15) }
        XCTAssertNotNil(ScribbleGestureDetector.region(for: horizontal, duration: 0.8))
        let denselySampled = (0...2400).map { index -> ScribblePoint in
            let leg = index / 300, fraction = Double(index % 300) / 300
            return ScribblePoint(x: leg.isMultiple(of: 2) ? fraction * 100 : (1 - fraction) * 100, y: 15)
        }
        XCTAssertNotNil(ScribbleGestureDetector.region(for: denselySampled, duration: 0.8))
    }

    func testRotationAndTranslationDoNotChangeClassification() {
        for angle in [Double.pi / 6, Double.pi / 2, Double.pi * 0.8] {
            let rotated = zigzag.map {
                ScribblePoint(x: 1200 + $0.x * cos(angle) - $0.y * sin(angle),
                              y: -400 + $0.x * sin(angle) + $0.y * cos(angle))
            }
            XCTAssertNotNil(ScribbleGestureDetector.region(for: rotated, duration: 0.8))
        }
    }

    func testDenseSamplingAndSmallJitterPreserveGesture() {
        var sampled: [ScribblePoint] = []
        for index in 1..<zigzag.count {
            let a = zigzag[index - 1], b = zigzag[index]
            for step in 0..<20 {
                let t = Double(step) / 20
                sampled.append(ScribblePoint(x: a.x + (b.x - a.x) * t,
                                             y: a.y + (b.y - a.y) * t + (step.isMultiple(of: 2) ? 0.2 : -0.2)))
            }
        }
        sampled.append(zigzag.last!)
        XCTAssertNotNil(ScribbleGestureDetector.region(for: sampled, duration: 1))
    }

    func testRejectsLinesCirclesAndSmoothWaves() {
        let line = (0..<100).map { ScribblePoint(x: Double($0), y: Double($0) / 2) }
        let circle = (0...240).map { index in
            let angle = Double(index) * Double.pi * 6 / 240
            return ScribblePoint(x: 50 * cos(angle), y: 50 * sin(angle))
        }
        let wave = (0...400).map { index in
            ScribblePoint(x: Double(index) / 2, y: 30 * sin(Double(index) * .pi / 25))
        }
        for points in [line, circle, wave] {
            XCTAssertNil(ScribbleGestureDetector.region(for: points, duration: 1))
        }
    }

    func testRejectsInsufficientReversalsSlowDrawingAndOversize() {
        XCTAssertNil(ScribbleGestureDetector.region(for: Array(zigzag.prefix(5)), duration: 0.5))
        XCTAssertNil(ScribbleGestureDetector.region(for: zigzag, duration: 4))
        XCTAssertNil(ScribbleGestureDetector.region(for: zigzag.map { ScribblePoint(x: $0.x * 8, y: $0.y * 8) }, duration: 1))
        XCTAssertNil(ScribbleGestureDetector.region(for: zigzag.map { ScribblePoint(x: $0.x / 10, y: $0.y / 10) }, duration: 1))
    }

    func testRejectsInvalidAndNoisyInput() {
        XCTAssertNil(ScribbleGestureDetector.region(for: [], duration: 1))
        XCTAssertNil(ScribbleGestureDetector.region(for: Array(repeating: ScribblePoint(x: 3, y: 3), count: 30), duration: 1))
        XCTAssertNil(ScribbleGestureDetector.region(for: Array(repeating: zigzag, count: 500).flatMap { $0 }, duration: 1))
        for duration in [Double.nan, .infinity, -1, 0] {
            XCTAssertNil(ScribbleGestureDetector.region(for: zigzag, duration: duration))
        }
        for invalid in [Double.nan, .infinity, -.infinity, Double.greatestFiniteMagnitude] {
            var points = zigzag
            points[3].x = invalid
            XCTAssertNil(ScribbleGestureDetector.region(for: points, duration: 1))
        }
        let noisyLine = (0..<200).map { ScribblePoint(x: Double($0), y: $0.isMultiple(of: 2) ? 0.4 : -0.4) }
        XCTAssertNil(ScribbleGestureDetector.region(for: noisyLine, duration: 1))
    }
}
