// Renders the 1024 px app icon: the brand dot-grid backdrop with the white ribbon "A".
// Usage: swiftc -O -parse-as-library AlyveWall/Engine/*.swift Tools/MakeIcon.swift -o /tmp/makeicon
//        /tmp/makeicon Tools/logo-a.png AlyveWall/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

@main
struct MakeIcon {
    static func main() {
        let args = CommandLine.arguments
        guard args.count >= 3, let logo = NSImage(contentsOfFile: args[1])?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            fatalError("usage: makeicon <logo.png> <out.png>")
        }
        let size = 1024.0
        let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        Brand.drawBackdrop(ctx, width: size, height: size, grid: true, pitch: 11)

        // The logo art's glyph spans about 83% of its canvas; aim for a glyph ~60% of the icon.
        let drawn = size * 0.6 / 0.83
        let rect = CGRect(x: (size - drawn) / 2, y: (size - drawn) / 2 + 4, width: drawn, height: drawn)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 46, color: CGColor(srgbRed: 0, green: 0, blue: 0.05, alpha: 0.6))
        ctx.interpolationQuality = .high
        ctx.draw(logo, in: rect)
        ctx.restoreGState()

        let out = URL(fileURLWithPath: args[2])
        let d = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(d, ctx.makeImage()!, nil)
        CGImageDestinationFinalize(d)
    }
}
