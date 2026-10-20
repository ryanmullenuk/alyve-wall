import CoreGraphics
import CoreText
import Foundation

/// Draws one frame of a wallpaper at any size. The preview and every export use this same code,
/// so what you see is what you save.
///
/// Everything is a function of `phase` (0 ..< 1 through the loop) and every motion makes a
/// whole number of cycles per loop, so frame 0 follows the last frame without a jump.
///
/// Soft layers (colour fields, aurora, lava, clouds) are drawn into a small offscreen bitmap and
/// scaled up, which is both fast and naturally blurred. Crisp things (stars, rain, petals, the
/// logo) are drawn at full resolution. Not thread-safe: give each thread its own renderer.
final class WallpaperRenderer: @unchecked Sendable {
    let config: WallpaperConfig
    let width: Int
    let height: Int
    let overlay: CGImage?
    let watermark: Bool

    private let W: Double
    private let H: Double
    /// Shorter and longer side.
    private let S: Double
    private let D: Double
    /// One thousandth of the shorter side, so sizes look the same at every resolution.
    private let u: Double
    private let colors: [RGB]
    private let tau = Double.pi * 2
    private let space = CGColorSpace(name: CGColorSpace.sRGB)!

    private let layer: CGContext
    private let lw: Double
    private let lh: Double

    init(config: WallpaperConfig, width: Int, height: Int, overlay: CGImage?, watermark: Bool) {
        self.config = config
        self.width = width
        self.height = height
        self.overlay = overlay
        self.watermark = watermark
        W = Double(width)
        H = Double(height)
        S = min(W, H)
        D = max(W, H)
        u = S / 1000
        var c = config.colors
        if c.isEmpty { c = Palette.all[0].colors }
        if c.count == 1 { c.append(c[0].lighter(0.4)) }
        colors = c

        // Offscreen soft layer: at most ~560 px on its long side.
        let factor = max(1, Int((D / 560).rounded(.up)))
        let lwi = max(8, width / factor)
        let lhi = max(8, height / factor)
        lw = Double(lwi)
        lh = Double(lhi)
        layer = CGContext(data: nil, width: lwi, height: lhi, bitsPerComponent: 8, bytesPerRow: lwi * 4,
                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        layer.translateBy(x: 0, y: lh)
        layer.scaleBy(x: 1, y: -1)
        layer.interpolationQuality = .high
    }

    // MARK: - Public

    func makeImage(phase: Double) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        draw(in: ctx, phase: phase)
        return ctx.makeImage()
    }

    /// Draws a full frame into `ctx`, which must be `width` × `height` pixels with a default CTM.
    func draw(in ctx: CGContext, phase: Double) {
        let p = phase - floor(phase)
        ctx.saveGState()
        ctx.translateBy(x: 0, y: H)
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high
        ctx.setShouldAntialias(true)

        let full = CGRect(x: 0, y: 0, width: W, height: H)
        if let img = overlay, config.overlay.placement == .background {
            ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            ctx.fill(full)
            let k = max(W / Double(img.width), H / Double(img.height))
            let iw = Double(img.width) * k
            let ih = Double(img.height) * k
            drawImage(img, in: CGRect(x: (W - iw) / 2, y: (H - ih) / 2, width: iw, height: ih), ctx: ctx)
            drawSoftLayer(ctx, p: p, alpha: config.overlay.tint)
        } else {
            drawSoftLayer(ctx, p: p, alpha: 1)
        }

        drawForeground(ctx, p: p)
        if config.dotGrid { Brand.drawGrid(ctx, width: W, height: H, pitch: max(3, S / 150)) }

        if let img = overlay, config.overlay.placement == .logo { drawLogo(img, ctx: ctx, p: p) }
        if watermark { drawWatermark(ctx) }
        ctx.restoreGState()
    }

    // MARK: - Helpers

    private var I: Double { 0.35 + 0.65 * config.intensity }
    private var sizeF: Double { 0.5 + config.size }

    private func cyc(_ base: Double) -> Int { config.cycles(base) }

    private func fract(_ x: Double) -> Double { x - floor(x) }

    private func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = min(1, max(0, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

    private func rng(_ salt: UInt64) -> SplitMix64 { SplitMix64(seed: config.seed &* 0x2545_F491_4F6C_DD1D ^ salt) }

    /// Palette colour at `t`, wrapping round so the last colour blends back into the first.
    private func sample(_ t: Double) -> RGB {
        let n = Double(colors.count)
        let x = fract(t) * n
        let i = Int(x) % colors.count
        return colors[i].mix(colors[(i + 1) % colors.count], x - floor(x))
    }

    private var brightest: RGB { colors.max { $0.luminance < $1.luminance } ?? .white }

    /// Draws `img` upright into `rect` (top-left coordinates) of a flipped context.
    private func drawImage(_ img: CGImage, in rect: CGRect, ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(img, in: CGRect(origin: .zero, size: rect.size))
        ctx.restoreGState()
    }

    private func gradient(_ stops: [(RGB, Double, Double)]) -> CGGradient {
        CGGradient(colorsSpace: space, colors: stops.map { $0.0.cg($0.1) } as CFArray, locations: stops.map { CGFloat($0.2) })!
    }

    private func glow(_ ctx: CGContext, x: Double, y: Double, r: Double, stops: [(RGB, Double, Double)]) {
        let c = CGPoint(x: x, y: y)
        ctx.drawRadialGradient(gradient(stops), startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
    }

    // MARK: - Soft layer

    private func drawSoftLayer(_ ctx: CGContext, p: Double, alpha: Double) {
        layer.saveGState()
        layer.clear(CGRect(x: 0, y: 0, width: lw, height: lh))
        switch config.style {
        case .gradient: drawField(p: p, dim: 1, amp: 0.36, blobAlpha: 0.55 + 0.4 * config.intensity)
        case .aurora: drawAurora(p: p)
        case .lavaLamp: drawLava(p: p)
        case .bokeh: drawField(p: p, dim: 0.5, amp: 0.25, blobAlpha: 0.8)
        case .starfield: drawField(p: p, dim: 0.22, amp: 0.2, blobAlpha: 0.7)
        case .rain: drawField(p: p, dim: 0.42, amp: 0.2, blobAlpha: 0.7)
        case .snow: drawField(p: p, dim: 0.75, amp: 0.2, blobAlpha: 0.75)
        case .dots: drawField(p: p, dim: 0.14, amp: 0.25, blobAlpha: 0.6)
        case .fireflies: drawField(p: p, dim: 0.26, amp: 0.2, blobAlpha: 0.7)
        case .clouds:
            drawField(p: p, dim: 0.95, amp: 0.15, blobAlpha: 0.7)
            drawClouds(p: p)
        case .petals: drawField(p: p, dim: 0.85, amp: 0.25, blobAlpha: 0.75)
        case .ripples: drawField(p: p, dim: 0.7, amp: 0.22, blobAlpha: 0.75)
        }
        layer.restoreGState()
        guard let img = layer.makeImage() else { return }
        ctx.saveGState()
        ctx.setAlpha(alpha)
        drawImage(img, in: CGRect(x: 0, y: 0, width: W, height: H), ctx: ctx)
        ctx.restoreGState()
    }

    /// A drifting mesh of colour: a slowly turning linear gradient through the palette with a
    /// large soft blob of each colour orbiting over it.
    private func drawField(p: Double, dim: Double, amp: Double, blobAlpha: Double) {
        let c = layer
        var r = rng(0xF1E1D)
        let angle = r.range(0, tau) + 0.45 * sin(tau * Double(cyc(1)) * p)
        let len = hypot(lw, lh) / 2
        let start = CGPoint(x: lw / 2 - cos(angle) * len, y: lh / 2 - sin(angle) * len)
        let end = CGPoint(x: lw / 2 + cos(angle) * len, y: lh / 2 + sin(angle) * len)
        let n = colors.count
        let stops = colors.enumerated().map { ($0.element, 1.0, Double($0.offset) / Double(n - 1)) }
        c.drawLinearGradient(gradient(stops), start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

        for col in colors {
            let ka = Double(cyc(1) * r.int(1, 2))
            let kb = Double(cyc(1) * r.int(1, 2))
            let px = r.range(0, tau), py = r.range(0, tau)
            let ox = r.range(-0.15, 0.15), oy = r.range(-0.15, 0.15)
            let x = (0.5 + ox + amp * sin(tau * ka * p + px)) * lw
            let y = (0.5 + oy + amp * cos(tau * kb * p + py)) * lh
            let rad = max(lw, lh) * r.range(0.4, 0.65)
            glow(c, x: x, y: y, r: rad, stops: [(col, blobAlpha, 0), (col, blobAlpha * 0.5, 0.5), (col, 0, 1)])
        }
        if dim < 1 {
            c.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1 - dim))
            c.fill(CGRect(x: 0, y: 0, width: lw, height: lh))
        }
    }

    /// Curtains of light: many thin vertical gradient strips that follow a wavy baseline.
    private func drawAurora(p: Double) {
        let c = layer
        let base = colors[0]
        c.drawLinearGradient(gradient([(base.scaled(0.12), 1, 0), (base.scaled(0.35).mix(colors.last!, 0.08), 1, 1)]),
                             start: .zero, end: CGPoint(x: 0, y: lh), options: [])
        c.setBlendMode(.plusLighter)
        let ribbons = colors.count > 2 ? Array(colors.dropFirst().prefix(4)) : colors
        var r = rng(0xA0A0)
        let steps = 110
        let dx = lw / Double(steps)
        for (i, col) in ribbons.enumerated() {
            let baseY = lh * (0.28 + 0.13 * Double(i) + r.range(-0.04, 0.04))
            let amp = lh * r.range(0.035, 0.07)
            let k1 = Double(cyc(1) + r.int(0, 1)), k2 = Double(cyc(1) + r.int(0, 1))
            let f1 = r.range(0.8, 1.6), f2 = r.range(2, 3.5)
            let p1 = r.range(0, tau), p2 = r.range(0, tau), p3 = r.range(0, tau), p4 = r.range(0, tau)
            for s in 0...steps {
                let x = Double(s) * dx
                let xn = x / lw
                let y = baseY + amp * sin(tau * (xn * f1 + k1 * p) + p1) + amp * 0.5 * sin(tau * (xn * f2 - k2 * p) + p2)
                let height = lh * (0.16 + 0.14 * (0.5 + 0.5 * sin(tau * (xn * 2.5 + k1 * p) + p3))) * (0.6 + 0.8 * config.size)
                let bright = (0.35 + 0.65 * (0.5 + 0.5 * sin(tau * (xn * 3.7 - k2 * p) + p4))) * I * 0.75
                let below = lh * 0.07
                c.saveGState()
                c.clip(to: CGRect(x: x, y: y - height, width: dx * 1.8, height: height + below))
                c.drawLinearGradient(gradient([(col, 0, 0), (col, bright * 0.45, 0.55), (col.lighter(0.2), bright, 0.8), (col, bright * 0.25, 0.9), (col, 0, 1)]),
                                     start: CGPoint(x: 0, y: y - height), end: CGPoint(x: 0, y: y + below), options: [])
                c.restoreGState()
            }
        }
        c.setBlendMode(.normal)
    }

    /// Metaballs computed per pixel into the soft layer: wax blobs rising and sinking in a lamp.
    private func drawLava(p: Double) {
        guard let data = layer.data else { return }
        let w = Int(lw), h = Int(lh)
        let bpr = layer.bytesPerRow
        let px = data.bindMemory(to: UInt8.self, capacity: bpr * h)
        let s = min(lw, lh)

        struct Blob { var x, y, r2: Double; var c: RGB }
        var r = rng(0x1A7A)
        let wax = colors.count > 1 ? Array(colors.dropFirst()) : colors
        let count = 5 + Int(config.density * 7)
        var blobs: [Blob] = []
        for i in 0..<count {
            let rad = s * r.range(0.08, 0.14) * (0.6 + 0.9 * config.size)
            let k = Double(cyc(0.6) + r.int(0, 1))
            let m = Double(cyc(0.5) + r.int(0, 1))
            let x0 = r.range(0.15, 0.85)
            let ph = r.range(0, tau), ph2 = r.range(0, tau)
            let x = (x0 + 0.08 * sin(tau * m * p + ph2)) * lw
            let y = (0.5 - 0.6 * cos(tau * k * p + ph)) * lh
            blobs.append(Blob(x: x, y: y, r2: rad * rad, c: wax[i % wax.count]))
        }
        // Pools of wax resting at the bottom and top of the lamp.
        blobs.append(Blob(x: lw * 0.5, y: lh * 1.12, r2: pow(s * 0.42, 2), c: wax[0]))
        blobs.append(Blob(x: lw * 0.5, y: -lh * 0.1, r2: pow(s * 0.22, 2), c: wax[wax.count - 1]))

        let top = colors[0].scaled(0.55), bottom = colors[0].scaled(0.22)
        let intensity = I
        for y in 0..<h {
            let fy = Double(y) + 0.5
            let bg = top.mix(bottom, fy / lh)
            let row = px + y * bpr
            for x in 0..<w {
                let fx = Double(x) + 0.5
                var f = 0.0, cr = 0.0, cg = 0.0, cb = 0.0
                for b in blobs {
                    let dx = fx - b.x, dy = fy - b.y
                    let v = b.r2 / (dx * dx + dy * dy + 0.01)
                    f += v; cr += b.c.r * v; cg += b.c.g * v; cb += b.c.b * v
                }
                let t = smoothstep(0.85, 1.15, f)
                let shade = 0.75 + 0.35 * min(1, max(0, (f - 1) / 1.5))
                let halo = min(1, f) * min(1, f) * 0.2 * intensity
                let wr = cr / f, wg = cg / f, wb = cb / f
                let outR = (bg.r + (wr - bg.r) * halo) * (1 - t) + wr * shade * t
                let outG = (bg.g + (wg - bg.g) * halo) * (1 - t) + wg * shade * t
                let outB = (bg.b + (wb - bg.b) * halo) * (1 - t) + wb * shade * t
                let o = row + x * 4
                o[0] = UInt8(min(255, max(0, outR * 255)))
                o[1] = UInt8(min(255, max(0, outG * 255)))
                o[2] = UInt8(min(255, max(0, outB * 255)))
                o[3] = 255
            }
        }
    }

    private func drawClouds(p: Double) {
        let c = layer
        var r = rng(0xC10D)
        let count = 4 + Int(config.density * 8)
        let s = min(lw, lh)
        struct Cloud { var x0, y0, scale: Double; var k: Int; var seed: UInt64 }
        var clouds: [Cloud] = (0..<count).map { _ in
            Cloud(x0: r.unit(), y0: r.range(0.04, 0.85), scale: r.range(0.55, 1.3), k: cyc(0.3) + r.int(0, 1), seed: r.next())
        }
        clouds.sort { $0.scale < $1.scale }
        let white = brightest.lighter(0.75)
        let shadow = colors[0].mix(.black, 0.2)
        for cl in clouds {
            let cw = s * 0.55 * cl.scale * (0.6 + 0.8 * config.size)
            let cx = fract(cl.x0 + Double(cl.k) * p) * (lw + 2 * cw) - cw
            let cy = cl.y0 * lh
            var pr = SplitMix64(seed: cl.seed)
            let puffs = pr.int(6, 9)
            for _ in 0..<puffs {
                let dx = pr.range(-0.5, 0.5) * cw, dy = pr.range(-0.14, 0.08) * cw
                let rad = cw * pr.range(0.2, 0.34)
                glow(c, x: cx + dx, y: cy + dy + rad * 0.3, r: rad * 1.05, stops: [(shadow, 0.16 * I, 0), (shadow, 0, 1)])
                glow(c, x: cx + dx, y: cy + dy, r: rad, stops: [(white, 0.7 * I, 0), (white, 0.45 * I, 0.55), (white, 0, 1)])
            }
        }
    }

    // MARK: - Foreground

    private func drawForeground(_ ctx: CGContext, p: Double) {
        ctx.saveGState()
        switch config.style {
        case .gradient, .lavaLamp, .clouds: break
        case .aurora: drawTwinkles(ctx, p: p, count: 40 + Int(config.density * 120), maxY: 0.6)
        case .bokeh: drawBokeh(ctx, p: p)
        case .starfield: drawStarfield(ctx, p: p)
        case .rain: drawRain(ctx, p: p)
        case .snow: drawSnow(ctx, p: p)
        case .dots: drawDots(ctx, p: p)
        case .fireflies: drawFireflies(ctx, p: p)
        case .petals: drawPetals(ctx, p: p)
        case .ripples: drawRipples(ctx, p: p)
        }
        ctx.restoreGState()
    }

    private func drawTwinkles(_ ctx: CGContext, p: Double, count: Int, maxY: Double) {
        var r = rng(0x7111)
        for _ in 0..<count {
            let x = r.unit() * W, y = r.unit() * H * maxY
            let k = Double(cyc(1) + r.int(0, 2))
            let a = (0.3 + 0.7 * (0.5 + 0.5 * sin(tau * k * p + r.range(0, tau)))) * r.range(0.3, 0.9) * I
            let rad = u * r.range(0.8, 2.2) * sizeF
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: a))
            ctx.fillEllipse(in: CGRect(x: x - rad, y: y - rad, width: rad * 2, height: rad * 2))
        }
    }

    private func drawBokeh(_ ctx: CGContext, p: Double) {
        ctx.setBlendMode(.screen)
        var r = rng(0xB0CE)
        let count = 12 + Int(config.density * 50)
        for _ in 0..<count {
            let x0 = r.unit(), y0 = r.unit()
            let rad = S * r.range(0.025, 0.11) * sizeF
            let col = colors[r.int(0, colors.count - 1)].lighter(0.35)
            let k1 = Double(cyc(0.5) + r.int(0, 1)), k2 = Double(cyc(0.5) + r.int(0, 1)), k3 = Double(cyc(1) + r.int(0, 1))
            let p1 = r.range(0, tau), p2 = r.range(0, tau), p3 = r.range(0, tau)
            let x = (x0 + 0.06 * sin(tau * k1 * p + p1)) * W
            let y = (y0 + 0.06 * cos(tau * k2 * p + p2)) * H
            let a = I * r.range(0.15, 0.5) * (0.65 + 0.35 * sin(tau * k3 * p + p3))
            glow(ctx, x: x, y: y, r: rad, stops: [(col, a * 0.7, 0), (col, a * 0.8, 0.78), (col, a, 0.92), (col, 0, 1)])
        }
    }

    private func drawStarfield(_ ctx: CGContext, p: Double) {
        var r = rng(0x57A5)
        let count = 150 + Int(config.density * 650)
        let k = cyc(1)
        let cx = W / 2, cy = H / 2
        let reach = D * 0.78
        let tint = brightest.lighter(0.7)
        ctx.setLineCap(.round)
        for _ in 0..<count {
            let theta = r.range(0, tau)
            let z0 = r.unit()
            let kk = Double(k + r.int(0, 1))
            let z = fract(z0 + kk * p)
            let tail = max(0, z - 0.035 * sizeF)
            let d1 = z * z * reach + S * 0.01
            let d0 = tail * tail * reach + S * 0.01
            let dx = cos(theta), dy = sin(theta)
            let a = I * min(1, z * 5) * r.range(0.5, 1)
            ctx.setStrokeColor(tint.cg(a))
            ctx.setLineWidth(u * (0.6 + 3.2 * z) * sizeF)
            ctx.move(to: CGPoint(x: cx + dx * d0, y: cy + dy * d0))
            ctx.addLine(to: CGPoint(x: cx + dx * d1, y: cy + dy * d1))
            ctx.strokePath()
        }
    }

    private func drawRain(_ ctx: CGContext, p: Double) {
        var r = rng(0x4A1F)
        let count = 60 + Int(config.density * 360)
        let slant = 0.12
        let k = cyc(6)
        let col = brightest.lighter(0.6)
        ctx.setLineCap(.round)
        for _ in 0..<count {
            let x0 = r.unit(), y0 = r.unit(), depth = r.unit()
            let kk = Double(k + Int(depth * 3))
            let len = H * (0.025 + 0.05 * depth) * sizeF
            let y = fract(y0 + kk * p) * (H + len * 2) - len
            let x = x0 * (W + slant * H) - slant * y
            ctx.setStrokeColor(col.cg(I * (0.15 + 0.45 * depth)))
            ctx.setLineWidth(u * (0.8 + 1.8 * depth) * sqrt(sizeF))
            ctx.move(to: CGPoint(x: x, y: y))
            ctx.addLine(to: CGPoint(x: x + slant * len, y: y - len))
            ctx.strokePath()
        }
    }

    private func drawSnow(_ ctx: CGContext, p: Double) {
        var r = rng(0x5A0F)
        let count = 60 + Int(config.density * 420)
        let k = cyc(1.5)
        for _ in 0..<count {
            let x0 = r.unit(), y0 = r.unit(), depth = r.unit()
            let kk = Double(k + Int(depth * 2))
            let m = Double(cyc(0.8) + r.int(0, 1))
            let ph = r.range(0, tau)
            let rad = S * (0.0025 + 0.0075 * depth) * sizeF
            let y = fract(y0 + kk * p) * (H + 4 * rad) - 2 * rad
            let x = fract(x0 + 0.03 * sin(tau * m * p + ph)) * W
            let a = I * (0.45 + 0.5 * depth)
            if rad < 3 * u {
                ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: a))
                ctx.fillEllipse(in: CGRect(x: x - rad, y: y - rad, width: rad * 2, height: rad * 2))
            } else {
                glow(ctx, x: x, y: y, r: rad * 1.4, stops: [(.white, a, 0), (.white, a * 0.9, 0.55), (.white, 0, 1)])
            }
        }
    }

    private func drawDots(_ ctx: CGContext, p: Double) {
        let spacing = S * (0.085 - 0.05 * config.density)
        let cols = Int(W / spacing) + 2, rows = Int(H / spacing) + 2
        let ox = (W - Double(cols - 1) * spacing) / 2, oy = (H - Double(rows - 1) * spacing) / 2
        let k = Double(cyc(1)), k2 = Double(cyc(0.5))
        let maxR = spacing * 0.48
        for j in 0..<rows {
            for i in 0..<cols {
                let x = ox + Double(i) * spacing, y = oy + Double(j) * spacing
                let d = hypot(x - W / 2, y - H / 2) / S
                let wave = 0.5 + 0.5 * sin(tau * (k * p - d * 1.6))
                let rad = min(maxR, spacing * 0.42 * (0.22 + 0.78 * wave) * (0.6 + 0.8 * config.size))
                let col = sample(x / W * 0.5 + y / H * 0.5 + k2 * p)
                ctx.setFillColor(col.cg(I * (0.5 + 0.5 * wave)))
                ctx.fillEllipse(in: CGRect(x: x - rad, y: y - rad, width: rad * 2, height: rad * 2))
            }
        }
    }

    private func drawFireflies(_ ctx: CGContext, p: Double) {
        ctx.setBlendMode(.plusLighter)
        var r = rng(0xF1F1)
        let count = 15 + Int(config.density * 100)
        let warm = RGB(1, 0.9, 0.45)
        for _ in 0..<count {
            let x0 = r.unit(), y0 = r.unit()
            let ax = r.range(0.03, 0.12), ay = r.range(0.03, 0.1)
            let a = Double(cyc(0.5) + r.int(0, 1)), b = Double(cyc(0.5) + r.int(0, 2))
            let p1 = r.range(0, tau), p2 = r.range(0, tau), p3 = r.range(0, tau), p4 = r.range(0, tau)
            let blinkK = Double(cyc(1) + r.int(0, 2))
            let col = warm.mix(colors[r.int(0, colors.count - 1)].lighter(0.3), 0.45)
            let size = S * 0.06 * sizeF * r.range(0.6, 1.3)
            let x = (x0 + ax * sin(tau * a * p + p1) + 0.03 * sin(tau * (b + 1) * p + p2)) * W
            let y = (y0 + ay * cos(tau * b * p + p3)) * H
            let blink = pow(0.5 + 0.5 * sin(tau * blinkK * p + p4), 2.5)
            let al = I * blink
            glow(ctx, x: x, y: y, r: size, stops: [(col, al * 0.95, 0), (col, al * 0.5, 0.12), (col, al * 0.12, 0.45), (col, 0, 1)])
            glow(ctx, x: x, y: y, r: size * 0.16, stops: [(.white, al, 0), (.white, al * 0.6, 0.4), (.white, 0, 1)])
        }
    }

    private func drawPetals(_ ctx: CGContext, p: Double) {
        var r = rng(0x9E7A)
        let count = 14 + Int(config.density * 70)
        for _ in 0..<count {
            let x0 = r.unit(), y0 = r.unit(), depth = r.unit()
            let kk = Double(cyc(1) + Int(depth * 2))
            let m = Double(cyc(0.6) + r.int(0, 1))
            let spin = Double(r.int(-2, 2))
            let q = Double(cyc(0.8) + r.int(0, 1))
            let ph = r.range(0, tau), pr = r.range(0, tau), pt = r.range(0, tau)
            let L = S * (0.018 + 0.022 * depth) * sizeF
            let col = colors[r.int(colors.count > 2 ? 1 : 0, colors.count - 1)].lighter(0.35)
            let y = fract(y0 + kk * p) * (H + 4 * L) - 2 * L
            let x = fract(x0 + 0.06 * sin(tau * m * p + ph)) * W
            let rot = pr + tau * spin * p
            let sx = 0.25 + 0.75 * abs(cos(tau * q * p + pt))

            ctx.saveGState()
            ctx.translateBy(x: x, y: y)
            ctx.rotate(by: rot)
            ctx.scaleBy(x: sx, y: 1)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: L))
            path.addCurve(to: CGPoint(x: 0, y: -L * 0.8), control1: CGPoint(x: L * 0.95, y: L * 0.35), control2: CGPoint(x: L * 0.75, y: -L * 1.05))
            path.addQuadCurve(to: CGPoint(x: 0, y: -L * 0.55), control: CGPoint(x: 0, y: -L * 0.62))
            path.addQuadCurve(to: CGPoint(x: 0, y: -L * 0.8), control: CGPoint(x: 0, y: -L * 0.62))
            path.addCurve(to: CGPoint(x: 0, y: L), control1: CGPoint(x: -L * 0.75, y: -L * 1.05), control2: CGPoint(x: -L * 0.95, y: L * 0.35))
            ctx.addPath(path)
            ctx.clip()
            ctx.drawLinearGradient(gradient([(col, I * (0.65 + 0.3 * depth), 0), (col.lighter(0.5), I * (0.75 + 0.25 * depth), 1)]),
                                   start: CGPoint(x: 0, y: L), end: CGPoint(x: 0, y: -L), options: [])
            ctx.restoreGState()
        }
    }

    private func drawRipples(_ ctx: CGContext, p: Double) {
        ctx.setBlendMode(.screen)
        var r = rng(0x919E)
        let count = 3 + Int(config.density * 10)
        let k = cyc(0.5)
        let col = brightest.lighter(0.55)
        let maxR = S * (0.25 + 0.35 * config.size)
        for _ in 0..<count {
            let cx = r.unit() * W, cy = r.unit() * H
            let birth = r.unit()
            let kk = Double(k + r.int(0, 1))
            let age = fract(kk * p + birth)
            for j in 0..<3 {
                let a = age - Double(j) * 0.08
                guard a > 0 else { continue }
                let rad = a * maxR
                let alpha = I * 0.6 * pow(1 - a, 1.6) * (1 - Double(j) * 0.28)
                ctx.setStrokeColor(col.cg(alpha))
                ctx.setLineWidth(u * (2.6 - Double(j) * 0.6) * sizeF)
                ctx.strokeEllipse(in: CGRect(x: cx - rad, y: cy - rad * 0.92, width: rad * 2, height: rad * 1.84))
            }
        }
    }

    // MARK: - Overlay and watermark

    private func drawLogo(_ img: CGImage, ctx: CGContext, p: Double) {
        let o = config.overlay
        let w = S * o.scale
        let h = w * Double(img.height) / Double(max(1, img.width))
        let bob = o.float ? sin(tau * p) * S * 0.012 : 0
        let rect = CGRect(x: o.x * W - w / 2, y: o.y * H - h / 2 + bob, width: w, height: h)
        ctx.saveGState()
        ctx.setAlpha(o.opacity)
        ctx.setShadow(offset: .zero, blur: S * 0.02, color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.25))
        drawImage(img, in: rect, ctx: ctx)
        ctx.restoreGState()
    }

    private func drawWatermark(_ ctx: CGContext) {
        let size = max(11, S * 0.026)
        let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil)
            ?? CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.72),
            NSAttributedString.Key(kCTKernAttributeName as String): size * 0.18,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "ALYVE WALL", attributes: attrs))
        let bounds = CTLineGetImageBounds(line, ctx)
        let margin = S * 0.035
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: size * 0.5, color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.45))
        // Portrait: bottom centre, clear of the Lock Screen's torch and camera buttons and the
        // home bar. Landscape: bottom-right corner.
        if H > W {
            ctx.translateBy(x: (W - bounds.width) / 2 - bounds.minX, y: H - H * 0.075)
        } else {
            ctx.translateBy(x: W - margin - bounds.width - bounds.minX, y: H - margin)
        }
        ctx.scaleBy(x: 1, y: -1)
        ctx.textMatrix = .identity
        ctx.textPosition = .zero
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}
