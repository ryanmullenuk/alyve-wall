// Renders a contact sheet of every style and test exports, on the Mac, using the app's engine.
// Usage: swiftc -O AlyveWall/Engine/*.swift Tools/EngineHarness.swift -o /tmp/harness && /tmp/harness <outDir>
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

@main
struct Harness {
    static func main() throws {
        let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let tw = 270, th = 585
        let cols = 6
        let styles = WallpaperStyle.allCases
        let sheet = CGContext(data: nil, width: tw * cols, height: th * 2, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for (i, style) in styles.enumerated() {
            var c = WallpaperConfig()
            c.style = style
            c.colors = Palette.all[i % Palette.all.count].colors
            let start = Date()
            let r = WallpaperRenderer(config: c, width: tw, height: th, overlay: nil, watermark: i == 0)
            let img = r.makeImage(phase: 0.3)!
            print(style.title, String(format: "%.1f ms", Date().timeIntervalSince(start) * 1000))
            sheet.draw(img, in: CGRect(x: (i % cols) * tw, y: (1 - i / cols) * th, width: tw, height: th))
        }
        save(sheet.makeImage()!, out.appendingPathComponent("sheet.png"))

        // Loop seam check: phase 0 and phase 1 must be the same image.
        for style in styles {
            var c = WallpaperConfig(); c.style = style; c.speed = 1.7
            let a = WallpaperRenderer(config: c, width: 120, height: 200, overlay: nil, watermark: false).makeImage(phase: 0)!
            let b = WallpaperRenderer(config: c, width: 120, height: 200, overlay: nil, watermark: false).makeImage(phase: 0.9999999)!
            print("seam", style.title, diff(a, b))
        }

        var c = WallpaperConfig(); c.style = .aurora; c.loopSeconds = 5
        let control = ExportControl()
        var t = Date()
        let mp4 = try Exporter.exportMP4(config: c, overlay: SendableImage(image: nil), size: ExportSize.mac[6], fps: 30, watermark: false,
                                         control: control) { _ in }
        print("4K mp4 5s:", Date().timeIntervalSince(t), mp4.path)
        try? FileManager.default.removeItem(at: out.appendingPathComponent("test.mp4"))
        try FileManager.default.copyItem(at: mp4, to: out.appendingPathComponent("test.mp4"))
        t = Date()
        c.style = .lavaLamp
        let live = try Exporter.exportLivePhoto(config: c, overlay: SendableImage(image: nil), size: ExportSize.livePhotoPremium, watermark: true,
                                                control: control) { _ in }
        print("live:", Date().timeIntervalSince(t), live.photo.path, live.video.path)
        for u in [live.photo, live.video] {
            try? FileManager.default.removeItem(at: out.appendingPathComponent("live." + u.pathExtension))
            try FileManager.default.copyItem(at: u, to: out.appendingPathComponent("live." + u.pathExtension))
        }
    }

    static func diff(_ a: CGImage, _ b: CGImage) -> Int {
        func bytes(_ i: CGImage) -> [UInt8] {
            var d = [UInt8](repeating: 0, count: i.width * i.height * 4)
            let ctx = CGContext(data: &d, width: i.width, height: i.height, bitsPerComponent: 8, bytesPerRow: i.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(i, in: CGRect(x: 0, y: 0, width: i.width, height: i.height))
            return d
        }
        return zip(bytes(a), bytes(b)).map { abs(Int($0) - Int($1)) }.max() ?? 0
    }

    static func save(_ img: CGImage, _ url: URL) {
        let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(d, img, nil)
        CGImageDestinationFinalize(d)
    }
}
