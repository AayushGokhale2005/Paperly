import UIKit
import PencilKit

/// Paper stays white even when the app chrome is dark. Render its ink in that same appearance.
enum PaperInk {
    static func color(_ color: UIColor) -> UIColor {
        color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
    }
    static func image(_ drawing: PKDrawing, from rect: CGRect, scale: CGFloat) -> UIImage {
        var result: UIImage!
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            result = drawing.image(from: rect, scale: scale)
        }
        return result
    }
}
