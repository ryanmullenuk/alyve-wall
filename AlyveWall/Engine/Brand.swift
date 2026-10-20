import CoreGraphics
import Foundation

/// The ALYVE WALL look: a dark mesh of teal, plum, ember and orange glows under a fine LED dot
/// grid. Used for the app icon, store artwork and the in-app background.
enum Brand {
    struct Bloom {
        var x, y, r: Double
        var color: RGB
        var alpha: Double
    }

    static let base = RGB(hex: 0x03051A)

    /// Positions are fractions of the canvas, top-left origin; radius is a fraction of the long side.
    static let blooms: [Bloom] = [
        Bloom(x: 0.5, y: 0.0, r: 0.7, color: RGB(hex: 0x050B2E), alpha: 0.9),
        Bloom(x: -0.08, y: 0.42, r: 0.48, color: RGB(hex: 0x12805F), alpha: 0.85),
        Bloom(x: 0.42, y: 0.48, r: 0.5, color: RGB(hex: 0x0B3A5A), alpha: 0.8),
        Bloom(x: -0.05, y: 0.76, r: 0.36, color: RGB(hex: 0x5C1556), alpha: 0.85),
        Bloom(x: 1.02, y: 0.72, r: 0.32, color: RGB(hex: 0x9A2420), alpha: 0.8),
        Bloom(x: 0.95, y: 1.02, r: 0.5, color: RGB(hex: 0xFF8C3E), alpha: 0.95),
    ]

    /// The palette offered in the app that matches the brand backdrop.
    static let palette = Palette(name: "Alyve", colors: [RGB(hex: 0x050B2E), RGB(hex: 0x12805F), RGB(hex: 0x5C1556), RGB(hex: 0xC2401E), RGB(hex: 0xFF8C3E)])

    /// Draws the backdrop into a context with the default (bottom-left origin) CTM.
    /// `drift` (0 ..< 1) moves the glows gently, for animated uses.
    static func drawBackdrop(_ ctx: CGContext, width: Double, height: Double, drift: Double = 0, grid: Bool = true, pitch: Double? = nil) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        ctx.saveGState()
        ctx.setFillColor(base.cg())
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let long = max(width, height)
        let tau = Double.pi * 2
        for (i, b) in blooms.enumerated() {
            let dx = 0.04 * sin(tau * drift + Double(i) * 1.7)
            let dy = 0.03 * cos(tau * drift + Double(i) * 2.3)
            let centre = CGPoint(x: (b.x + dx) * width, y: (1 - (b.y + dy)) * height)
            let g = CGGradient(colorsSpace: space, colors: [b.color.cg(b.alpha), b.color.cg(b.alpha * 0.45), b.color.cg(0)] as CFArray,
                               locations: [0, 0.5, 1])!
            ctx.drawRadialGradient(g, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: b.r * long, options: [])
        }
        ctx.restoreGState()
        if grid { drawGrid(ctx, width: width, height: height, pitch: pitch ?? max(3, min(width, height) / 150)) }
    }

    /// Dark gaps on a square lattice, so the light underneath reads as rows of glowing dots.
    static func drawGrid(_ ctx: CGContext, width: Double, height: Double, pitch: Double, alpha: Double = 0.55) {
        let line = max(1, pitch * 0.32)
        ctx.saveGState()
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: alpha))
        var v = 0.0
        while v < width {
            ctx.fill(CGRect(x: v, y: 0, width: line, height: height))
            v += pitch
        }
        v = 0
        while v < height {
            ctx.fill(CGRect(x: 0, y: v, width: width, height: line))
            v += pitch
        }
        ctx.restoreGState()
    }
}
