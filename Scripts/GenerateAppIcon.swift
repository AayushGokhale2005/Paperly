import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Usage: swift Scripts/GenerateAppIcon.swift Artwork/PaperlyMark.png <output.png>
// Preserve the transparent master; classic iPad app-icon assets use an opaque RGB backing.
guard CommandLine.arguments.count == 3 else {
    fatalError("Usage: GenerateAppIcon.swift <transparent-master.png> <app-icon.png>")
}
let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
      let mark = CGImageSourceCreateImageAtIndex(source, 0, nil),
      let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(data: nil, width: 1024, height: 1024,
                              bitsPerComponent: 8, bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    fatalError("Could not load logo or create the icon canvas")
}
context.setFillColor(CGColor(srgbRed: 0.025, green: 0.065, blue: 0.15, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
context.interpolationQuality = .high
let scale = min(1024 / CGFloat(mark.width), 1024 / CGFloat(mark.height))
let width = CGFloat(mark.width) * scale, height = CGFloat(mark.height) * scale
context.draw(mark, in: CGRect(x: (1024 - width) / 2, y: (1024 - height) / 2, width: width, height: height))
guard let rendered = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("Could not create PNG output")
}
CGImageDestinationAddImage(destination, rendered, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Could not write PNG") }
