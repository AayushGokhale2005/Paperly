import UIKit
import PencilKit

/// Transparent page preview: image objects use the same order/placement as the editor,
/// with editable ink composited above them. Paper templates and PDF remain separate layers.
enum PageThumbnailRenderer {
    static func png(drawing: PKDrawing, page: NotebookPage, images: [NotebookImage],
                    imageBytes: [UUID: Data], scale: CGFloat = 0.2) -> Data? {
        guard scale.isFinite, scale > 0, scale <= 1,
              page.width.isFinite, page.height.isFinite,
              page.width > 0, page.height > 0,
              page.width <= 20_000, page.height <= 20_000 else { return nil }
        let pageBounds = CGRect(x: 0, y: 0, width: page.width, height: page.height)
        let size = CGSize(width: ceil(pageBounds.width * scale), height: ceil(pageBounds.height * scale))
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1
        let ink = PaperInk.image(drawing, from: pageBounds, scale: scale)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            cg.scaleBy(x: scale, y: scale)
            cg.clip(to: pageBounds)
            for item in images {
                guard item.x.isFinite, item.y.isFinite, item.rotation.isFinite,
                      item.width.isFinite, item.height.isFinite,
                      item.width >= 1, item.height >= 1,
                      item.width <= 20_000, item.height <= 20_000,
                      let bytes = imageBytes[item.id],
                      let image = UIImage(data: bytes) else { continue }
                cg.saveGState()
                cg.translateBy(x: item.x + item.width / 2, y: item.y + item.height / 2)
                cg.rotate(by: item.rotation * .pi / 180)
                image.draw(in: CGRect(x: -item.width / 2, y: -item.height / 2,
                                      width: item.width, height: item.height))
                cg.restoreGState()
            }
            ink.draw(in: pageBounds)
        }.pngData()
    }
}
