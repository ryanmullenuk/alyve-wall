// Renders the 1024 px App Store icon using the app's own gradient engine plus a bold "A" mark.
// Usage: swiftc -O -parse-as-library AlyveWall/Engine/*.swift Tools/MakeIcon.swift -o /tmp/makeicon && /tmp/makeicon <out.png>
import AppKit
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

@main
struct MakeIcon {
    static func main() {
        let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png")
        let size = 1024
        var c = WallpaperConfig()
        c.style = .gradient
        c.colors = [RGB(hex: 0x2A0B5C), RGB(hex: 0x7B3FF2), RGB(hex: 0xF0479B), RGB(hex: 0xFF9E3D), RGB(hex: 0x29D3C4)]
        c.intensity = 0.95
        c.seed = 11
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        WallpaperRenderer(config: c, width: size, height: size, overlay: nil, watermark: false).draw(in: ctx, phase: 0.15)

        // Soft vignette for depth.
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let vignette = CGGradient(colorsSpace: space, colors: [CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 0.35)] as CFArray, locations: [0.55, 1])!
        ctx.drawRadialGradient(vignette, startCenter: CGPoint(x: 512, y: 512), startRadius: 0, endCenter: CGPoint(x: 512, y: 512), endRadius: 760, options: [])

        // The "A": heavy rounded system type, white with a soft glow.
        let base = CTFontCreateUIFontForLanguage(.system, 700, nil)!
        var traits: [CFString: Any] = [kCTFontWeightTrait: 0.62]
        let desc = CTFontDescriptorCreateWithAttributes([kCTFontTraitsAttribute: traits] as CFDictionary)
        var font = CTFontCreateCopyWithAttributes(base, 700, nil, desc)
        if let rounded = NSFontDescriptor(fontAttributes: [.family: "SF Pro Rounded"]).withSymbolicTraits(.bold) as NSFontDescriptor?,
           let f = NSFont(descriptor: rounded.addingAttributes([.traits: [NSFontDescriptor.TraitKey.weight: NSFont.Weight.black]]), size: 700) {
            font = f as CTFont
        }
        traits.removeAll()
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "A", attributes: attrs))
        let b = CTLineGetImageBounds(line, ctx)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 40, color: CGColor(srgbRed: 0.15, green: 0, blue: 0.3, alpha: 0.45))
        ctx.textPosition = CGPoint(x: 512 - b.midX, y: 512 - b.midY - 6)
        CTLineDraw(line, ctx)
        ctx.restoreGState()

        let d = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(d, ctx.makeImage()!, nil)
        CGImageDestinationFinalize(d)
    }
}
