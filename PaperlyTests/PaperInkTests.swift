import XCTest
import UIKit
import PencilKit
@testable import Paperly

@MainActor final class PaperInkTests: XCTestCase {
    func testWhitePaperCanvasKeepsLightInkAppearanceInsideDarkChrome() {
        let parent = UIViewController(); parent.overrideUserInterfaceStyle = .dark
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        window.rootViewController = parent; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        let canvas = PaperlyCanvasView(); parent.view.addSubview(canvas)
        parent.view.layoutIfNeeded(); canvas.updateTraitsIfNeeded()
        XCTAssertEqual(canvas.overrideUserInterfaceStyle, .light)
        XCTAssertEqual(parent.traitCollection.userInterfaceStyle, .dark)
        XCTAssertEqual(canvas.traitCollection.userInterfaceStyle, .light)
        let tool = DrawingTool.pen.pkTool(color: .label, width: 3) as! PKInkingTool
        var white: CGFloat = 1, alpha: CGFloat = 0
        XCTAssertTrue(tool.color.getWhite(&white, alpha: &alpha))
        XCTAssertLessThan(white, 0.05); XCTAssertEqual(alpha, 1)
    }
    func testBlackDrawingRemainsBlackWhenRenderedUnderDarkTraits() throws {
        let samples = [CGPoint(x: 10, y: 50), CGPoint(x: 90, y: 50)].enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.1, size: CGSize(width: 10, height: 10), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let drawing = PKDrawing(strokes: [PKStroke(ink: PKInk(.monoline, color: .black), path: PKStrokePath(controlPoints: samples, creationDate: Date()))])
        let serialized = drawing.dataRepresentation()
        var rendered: UIImage?
        UITraitCollection(userInterfaceStyle: .dark).performAsCurrent {
            rendered = PaperInk.image(drawing, from: CGRect(x: 0, y: 0, width: 100, height: 100), scale: 1)
        }
        let cg = try XCTUnwrap(rendered?.cgImage)
        var pixel = [UInt8](repeating: 0, count: 4)
        try pixel.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(UIColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
            context.translateBy(x: -50, y: -50); context.draw(cg, in: CGRect(x: 0, y: 0, width: 100, height: 100))
        }
        XCTAssertLessThan(pixel[0], 30); XCTAssertLessThan(pixel[1], 30); XCTAssertLessThan(pixel[2], 30)
        XCTAssertEqual(pixel[3], 255)
        XCTAssertEqual(drawing.dataRepresentation(), serialized, "Appearance fixes must not rewrite editable strokes")
    }
}
