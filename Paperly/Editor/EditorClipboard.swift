import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

struct ImportedImage: Sendable {
    let pngData: Data
    let width: Double
    let height: Double
}

enum ImageImportError: Error, LocalizedError {
    case invalidImage, unsupportedClipboardVersion, imageDimensionsTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidImage: "This file is not a readable image."
        case .unsupportedClipboardVersion: "This copied image uses an unsupported Paperly format."
        case .imageDimensionsTooLarge: "This image has unsupported pixel dimensions."
        }
    }
}

/// Pure byte conversion: performs no UIKit drawing, file access or clipboard access.
/// The caller can run this synchronous work outside the main actor.
enum ImageImportService {
    static let maximumPixelDimension = 2048

    static func normalizedPNG(_ data: Data) throws -> ImportedImage {
        guard data.count <= NotebookManifest.maximumImageBytes else { throw DocumentError.imageTooLarge }
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData,
                  [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0 else { throw ImageImportError.invalidImage }
        // Bound pathological source headers before asking ImageIO to decode any pixels.
        _ = try dimensions(source, maximumDimension: 32_768, maximumPixels: 100_000_000)
        let image = try thumbnail(source)
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData,
            UTType.png.identifier as CFString, 1, nil) else { throw ImageImportError.invalidImage }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ImageImportError.invalidImage }
        let png = output as Data
        guard png.count <= NotebookManifest.maximumImageBytes else { throw DocumentError.imageTooLarge }
        return ImportedImage(pngData: png, width: Double(image.width), height: Double(image.height))
    }

    fileprivate static func validatePNG(_ data: Data) throws {
        guard data.count <= NotebookManifest.maximumImageBytes else { throw DocumentError.imageTooLarge }
        guard data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]),
              let source = CGImageSourceCreateWithData(data as CFData,
                  [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetType(source).map({ $0 as String }) == UTType.png.identifier,
              CGImageSourceGetCount(source) == 1 else { throw ImageImportError.invalidImage }
        _ = try dimensions(source, maximumDimension: 8192, maximumPixels: 8192 * 8192)
        // Decode a bounded thumbnail to validate pixels without allocating the full image.
        _ = try thumbnail(source)
        guard CGImageSourceGetStatus(source) == .statusComplete else { throw ImageImportError.invalidImage }
    }

    private static func dimensions(_ source: CGImageSource, maximumDimension: Int, maximumPixels: Int) throws -> (Int, Int) {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width.isFinite, height.isFinite, width >= 1, height >= 1 else { throw ImageImportError.invalidImage }
        guard width <= Double(maximumDimension), height <= Double(maximumDimension),
              width * height <= Double(maximumPixels) else { throw ImageImportError.imageDimensionsTooLarge }
        return (Int(width), Int(height))
    }

    private static func thumbnail(_ source: CGImageSource) throws -> CGImage {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelDimension
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              image.width > 0, image.height > 0,
              max(image.width, image.height) <= maximumPixelDimension else { throw ImageImportError.invalidImage }
        return image
    }
}

/// Paperly's own versioned object representation; it does not claim Goodnotes compatibility.
/// Clipboard reads/writes belong exclusively to explicit UI actions in the caller.
struct ImageClipboardPayload: Codable, Sendable {
    static let pasteboardType = "app.paperly.image-selection"
    var formatVersion: Int = 1
    var image: NotebookImage
    var pngData: Data

    init(image: NotebookImage, pngData: Data) {
        self.image = image
        self.pngData = pngData
    }

    func encoded() throws -> Data {
        try validate()
        return try JSONEncoder().encode(self)
    }

    static func decode(_ data: Data) throws -> ImageClipboardPayload {
        // JSON base64 plus slash escaping can expand bytes; reject oversized envelopes first.
        guard data.count <= NotebookManifest.maximumImageBytes * 3 + 4096 else { throw DocumentError.imageTooLarge }
        let payload = try JSONDecoder().decode(Self.self, from: data)
        try payload.validate()
        return payload
    }

    private func validate() throws {
        guard formatVersion == 1 else { throw ImageImportError.unsupportedClipboardVersion }
        // Reuse document validation so copied geometry has exactly the persistence contract.
        var manifest = NotebookManifest(title: "Clipboard")
        manifest.pages[0].imageItems = [image]
        try manifest.validate()
        try ImageImportService.validatePNG(pngData)
    }
}
