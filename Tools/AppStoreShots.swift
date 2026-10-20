// Composes the App Store artwork from raw captures in AppStore/raw:
// captioned iPhone 6.9", iPad 13" and Mac screenshots, the 3840×1646 header banner and the IAP review shot.
// Usage: swiftc -O -parse-as-library AlyveWall/Engine/*.swift Tools/AppStoreShots.swift -o /tmp/shots && /tmp/shots AppStore
import AppKit
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

@main
struct AppStoreShots {
    struct Caption { let title: String; let sub: String }

    static let phoneCaptions = [
        Caption(title: "Wallpapers that\ncome alive", sub: "12 animated styles, from aurora to lava lamp"),
        Caption(title: "Your colours,\nyour vibe", sub: "Mix up to five colours or start from a palette"),
        Caption(title: "Add your logo\nor a photo", sub: "Drop in a PNG and place it anywhere"),
        Caption(title: "MP4 and\nLive Photo", sub: "Seamless loops for your Lock Screen and desktop"),
        Caption(title: "Made for your\nMac too", sub: "Desktop wallpapers right up to 5K"),
        Caption(title: "One purchase.\nNo subscription.", sub: "Premium removes the watermark and unlocks every size"),
    ]

    static let macCaptions = [
        Caption(title: "Wallpapers that come alive", sub: "12 animated styles, from aurora to lava lamp"),
        Caption(title: "Your colours, your vibe", sub: "Mix up to five colours or start from a palette"),
        Caption(title: "Add your logo or a photo", sub: "Drop in a PNG and place it anywhere"),
        Caption(title: "Every Mac, up to 5K", sub: "Seamless MP4 loops sized for your display"),
        Caption(title: "One purchase. No subscription.", sub: "Premium removes the watermark and unlocks every size"),
    ]

    static var root = URL(fileURLWithPath: "AppStore")

    static func main() throws {
        if CommandLine.arguments.count > 1 { root = URL(fileURLWithPath: CommandLine.arguments[1]) }
        let raw = root.appendingPathComponent("raw")
        let logo = load(root.deletingLastPathComponent().appendingPathComponent("Tools/logo-a.png"))!

        for (kind, size, folder) in [("phone", CGSize(width: 1320, height: 2868), "iphone-6.9"), ("pad", CGSize(width: 2064, height: 2752), "ipad-13")] {
            let dir = root.appendingPathComponent("screenshots/\(folder)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for (i, cap) in phoneCaptions.enumerated() {
                guard let shot = load(raw.appendingPathComponent("\(kind)-\(i + 1).png")) else { continue }
                save(portrait(shot: shot, size: size, caption: cap, pad: kind == "pad"), dir.appendingPathComponent(String(format: "%02d.png", i + 1)))
            }
        }

        let macDir = root.appendingPathComponent("screenshots/mac")
        try FileManager.default.createDirectory(at: macDir, withIntermediateDirectories: true)
        for (i, cap) in macCaptions.enumerated() {
            let n = i + 1
            let base = load(raw.appendingPathComponent("mac-\(n).png")) ?? load(raw.appendingPathComponent("mac-\(n)base.png"))
            guard let base else { continue }
            let sheet = load(raw.appendingPathComponent("mac-\(n)sheet.png"))
            save(mac(shot: base, sheet: sheet, caption: cap), macDir.appendingPathComponent(String(format: "%02d.png", n)))
        }

        if let phone = load(raw.appendingPathComponent("phone-1.png")), let macShot = load(raw.appendingPathComponent("mac-1.png")) {
            save(header(logo: logo, phone: phone, mac: macShot), root.appendingPathComponent("header-3840x1646.png"))
        }
        if let iap = load(raw.appendingPathComponent("phone-6.png")) {
            save(iap, root.appendingPathComponent("iap-review.png"))
        }
        print("done")
    }

    // MARK: - Layouts

    static func portrait(shot: CGImage, size: CGSize, caption: Caption, pad: Bool) -> CGImage {
        let ctx = canvas(size)
        Brand.drawBackdrop(ctx, width: size.width, height: size.height, grid: true, pitch: size.width / 150)
        let titleSize = size.width * (pad ? 0.062 : 0.083)
        let top = size.height * 0.045
        let titleBottom = drawText(ctx, caption.title, size: titleSize, weight: .heavy, centreX: size.width / 2, top: top, canvas: size, gradientFirstLine: true)
        let subBottom = drawText(ctx, caption.sub, size: titleSize * 0.36, weight: .medium, centreX: size.width / 2, top: titleBottom + titleSize * 0.35,
                                 canvas: size, alpha: 0.75)
        let w = size.width * (pad ? 0.74 : 0.78)
        let h = w * Double(shot.height) / Double(shot.width)
        let y = subBottom + size.height * 0.03
        let rect = CGRect(x: (size.width - w) / 2, y: y, width: w, height: h)
        device(ctx, shot: shot, rect: rect, radius: w * (pad ? 0.04 : 0.11), canvas: size)
        return ctx.makeImage()!
    }

    static func mac(shot: CGImage, sheet: CGImage?, caption: Caption) -> CGImage {
        let size = CGSize(width: 2880, height: 1800)
        let ctx = canvas(size)
        Brand.drawBackdrop(ctx, width: size.width, height: size.height, grid: true, pitch: 2880 / 220)
        let titleSize = 112.0
        let titleBottom = drawText(ctx, caption.title, size: titleSize, weight: .heavy, centreX: size.width / 2, top: 90, canvas: size, gradientFirstLine: true)
        let subBottom = drawText(ctx, caption.sub, size: 46, weight: .medium, centreX: size.width / 2, top: titleBottom + 28, canvas: size, alpha: 0.75)
        let bar = 64.0
        let w = 2240.0
        let h = w * Double(shot.height) / Double(shot.width)
        let windowRect = CGRect(x: (size.width - w) / 2, y: subBottom + 70, width: w, height: h + bar)
        // Window: shadow, title bar with traffic lights, then the app content.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -30), blur: 90, color: CGColor(gray: 0, alpha: 0.7))
        fill(ctx, rect: windowRect, radius: 26, canvas: size, color: CGColor(srgbRed: 0.09, green: 0.09, blue: 0.12, alpha: 1))
        ctx.restoreGState()
        ctx.saveGState()
        clip(ctx, rect: windowRect, radius: 26, canvas: size)
        let content = CGRect(x: windowRect.minX, y: windowRect.minY + bar, width: w, height: h)
        draw(ctx, shot, in: content, canvas: size)
        for (i, c) in [(1.0, 0.37, 0.34), (1.0, 0.74, 0.18), (0.16, 0.79, 0.25)].enumerated() {
            let r = 13.0
            let cx = windowRect.minX + 34 + Double(i) * 44
            let cy = windowRect.minY + bar / 2
            ctx.setFillColor(CGColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1))
            ctx.fillEllipse(in: flip(CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2), size))
        }
        if let sheet {
            ctx.setFillColor(CGColor(gray: 0, alpha: 0.45))
            ctx.fill(flip(content, size))
            let k = w / 2880.0
            let sw = Double(sheet.width) * k, sh = Double(sheet.height) * k
            let sr = CGRect(x: content.midX - sw / 2, y: content.minY + 8, width: sw, height: min(sh, content.height - 16))
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -20), blur: 60, color: CGColor(gray: 0, alpha: 0.6))
            fill(ctx, rect: sr, radius: 18, canvas: size, color: CGColor(gray: 0.05, alpha: 1))
            ctx.restoreGState()
            ctx.saveGState()
            clip(ctx, rect: sr, radius: 18, canvas: size)
            draw(ctx, sheet, in: CGRect(x: sr.minX, y: sr.minY, width: sw, height: sh), canvas: size)
            ctx.restoreGState()
        }
        ctx.restoreGState()
        stroke(ctx, rect: windowRect, radius: 26, canvas: size, color: CGColor(gray: 1, alpha: 0.16), width: 2)
        return ctx.makeImage()!
    }

    static func header(logo: CGImage, phone: CGImage, mac macShot: CGImage) -> CGImage {
        let size = CGSize(width: 3840, height: 1646)
        let ctx = canvas(size)
        Brand.drawBackdrop(ctx, width: size.width, height: size.height, grid: true, pitch: 3840 / 260)
        // Mac window on the right, phone overlapping it.
        let mw = 1820.0, mh = mw * Double(macShot.height) / Double(macShot.width)
        let mrect = CGRect(x: 1840, y: (size.height - mh) / 2 - 40, width: mw, height: mh)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -30), blur: 90, color: CGColor(gray: 0, alpha: 0.7))
        fill(ctx, rect: mrect, radius: 24, canvas: size, color: CGColor(gray: 0.05, alpha: 1))
        ctx.restoreGState()
        ctx.saveGState(); clip(ctx, rect: mrect, radius: 24, canvas: size); draw(ctx, macShot, in: mrect, canvas: size); ctx.restoreGState()
        stroke(ctx, rect: mrect, radius: 24, canvas: size, color: CGColor(gray: 1, alpha: 0.16), width: 2)
        let pw = 560.0, ph = pw * Double(phone.height) / Double(phone.width)
        device(ctx, shot: phone, rect: CGRect(x: 1640, y: (size.height - ph) / 2 + 30, width: pw, height: ph), radius: 70, canvas: size)

        // Logo and words on the left.
        let lw = 420.0
        let lrect = CGRect(x: 250, y: 330, width: lw, height: lw)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: CGColor(gray: 0, alpha: 0.55))
        draw(ctx, logo, in: lrect, canvas: size)
        ctx.restoreGState()
        let titleBottom = drawText(ctx, "ALYVE WALL", size: 128, weight: .heavy, left: 280, top: 820, canvas: size, gradientFirstLine: false, wordmark: true)
        _ = drawText(ctx, "Animated wallpapers for\niPhone and Mac", size: 70, weight: .semibold, left: 284, top: titleBottom + 40, canvas: size, alpha: 0.85)
        return ctx.makeImage()!
    }

    // MARK: - Drawing helpers (rects are top-left based; `flip` converts to CoreGraphics)

    static func canvas(_ size: CGSize) -> CGContext {
        CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    }

    static func flip(_ r: CGRect, _ size: CGSize) -> CGRect { CGRect(x: r.minX, y: size.height - r.maxY, width: r.width, height: r.height) }

    static func draw(_ ctx: CGContext, _ img: CGImage, in r: CGRect, canvas: CGSize) {
        ctx.interpolationQuality = .high
        ctx.draw(img, in: flip(r, canvas))
    }

    static func path(_ r: CGRect, radius: Double, canvas: CGSize) -> CGPath {
        CGPath(roundedRect: flip(r, canvas), cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    static func fill(_ ctx: CGContext, rect: CGRect, radius: Double, canvas: CGSize, color: CGColor) {
        ctx.addPath(path(rect, radius: radius, canvas: canvas)); ctx.setFillColor(color); ctx.fillPath()
    }

    static func clip(_ ctx: CGContext, rect: CGRect, radius: Double, canvas: CGSize) {
        ctx.addPath(path(rect, radius: radius, canvas: canvas)); ctx.clip()
    }

    static func stroke(_ ctx: CGContext, rect: CGRect, radius: Double, canvas: CGSize, color: CGColor, width: Double) {
        ctx.addPath(path(rect.insetBy(dx: width / 2, dy: width / 2), radius: radius, canvas: canvas))
        ctx.setStrokeColor(color); ctx.setLineWidth(width); ctx.strokePath()
    }

    /// A screenshot in a thin dark bezel with a soft shadow.
    static func device(_ ctx: CGContext, shot: CGImage, rect: CGRect, radius: Double, canvas: CGSize) {
        let bezel = rect.width * 0.022
        let outer = rect.insetBy(dx: -bezel, dy: -bezel)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -rect.width * 0.03), blur: rect.width * 0.08, color: CGColor(gray: 0, alpha: 0.7))
        fill(ctx, rect: outer, radius: radius + bezel, canvas: canvas, color: CGColor(srgbRed: 0.07, green: 0.07, blue: 0.09, alpha: 1))
        ctx.restoreGState()
        stroke(ctx, rect: outer, radius: radius + bezel, canvas: canvas, color: CGColor(gray: 1, alpha: 0.18), width: max(2, bezel * 0.18))
        ctx.saveGState()
        clip(ctx, rect: rect, radius: radius, canvas: canvas)
        draw(ctx, shot, in: rect, canvas: canvas)
        ctx.restoreGState()
    }

    static func font(_ size: Double, _ weight: NSFont.Weight) -> CTFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        if let d = base.fontDescriptor.withDesign(.rounded), let f = NSFont(descriptor: d, size: size) { return f as CTFont }
        return base as CTFont
    }

    static let glow = [RGB(hex: 0x8B5CF6), RGB(hex: 0xEC4899), RGB(hex: 0xFA9F3D)]

    /// Draws centred (or left-aligned) multi-line text from `top`; returns the bottom of the block.
    @discardableResult
    static func drawText(_ ctx: CGContext, _ text: String, size: Double, weight: NSFont.Weight, centreX: Double? = nil, left: Double? = nil,
                         top: Double, canvas: CGSize, alpha: Double = 1, gradientFirstLine: Bool = false, wordmark: Bool = false) -> Double {
        let f = font(size, weight)
        var y = top
        for (i, line) in text.split(separator: "\n").enumerated() {
            let attrs: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): f,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: alpha),
                NSAttributedString.Key(kCTKernAttributeName as String): wordmark ? size * 0.2 : (weight == .heavy ? -size * 0.01 : 0),
            ]
            let ct = CTLineCreateWithAttributedString(NSAttributedString(string: String(line), attributes: attrs))
            let width = CTLineGetTypographicBounds(ct, nil, nil, nil)
            let x = left ?? ((centreX ?? canvas.width / 2) - width / 2)
            let baseline = y + size * 0.95
            let origin = CGPoint(x: x, y: canvas.height - baseline)
            let useGradient = (gradientFirstLine && i == 0) || wordmark
            if useGradient {
                // Fill the glyphs with the brand gradient by clipping to their text-mode mask.
                ctx.saveGState()
                ctx.textMatrix = .identity
                ctx.textPosition = origin
                ctx.setTextDrawingMode(.clip)
                CTLineDraw(ct, ctx)
                let span = wordmark ? width * 0.52 : width
                let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: glow.map { $0.cg() } as CFArray, locations: [0, 0.5, 1])!
                ctx.drawLinearGradient(g, start: CGPoint(x: x, y: 0), end: CGPoint(x: x + span, y: 0), options: [])
                if wordmark {
                    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
                    ctx.fill(CGRect(x: x + span, y: 0, width: width, height: canvas.height))
                }
                ctx.restoreGState()
                ctx.setTextDrawingMode(.fill)
            } else {
                ctx.saveGState()
                ctx.setShadow(offset: .zero, blur: size * 0.2, color: CGColor(gray: 0, alpha: 0.35))
                ctx.textMatrix = .identity
                ctx.textPosition = origin
                CTLineDraw(ct, ctx)
                ctx.restoreGState()
            }
            y += size * 1.12
        }
        return y
    }

    static func load(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    static func save(_ img: CGImage, _ url: URL) {
        let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(d, img, nil)
        CGImageDestinationFinalize(d)
    }
}
