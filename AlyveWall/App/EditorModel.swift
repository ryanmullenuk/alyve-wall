import CoreGraphics
import Foundation
import ImageIO
import Observation
import SwiftUI
import UIKit

/// The wallpaper being edited, plus the one PNG or photo it carries. Saved automatically so the
/// design is still there next launch.
@MainActor
@Observable
final class EditorModel {
    var config: WallpaperConfig {
        didSet { if config != oldValue { scheduleSave() } }
    }
    var target: DeviceTarget = .iphone {
        didSet { UserDefaults.standard.set(target.rawValue, forKey: Keys.target) }
    }
    private(set) var overlay: CGImage?
    var isPlaying = true
    var showLockScreen = true

    private enum Keys {
        static let config = "alyvewall.config.v1"
        static let target = "alyvewall.target"
    }

    private var saveTask: Task<Void, Never>?

    init() {
        if let data = UserDefaults.standard.data(forKey: Keys.config),
           let saved = try? JSONDecoder().decode(WallpaperConfig.self, from: data) {
            config = saved
        } else {
            config = WallpaperConfig()
        }
        if let raw = UserDefaults.standard.string(forKey: Keys.target), let t = DeviceTarget(rawValue: raw) {
            target = t
        } else {
            #if targetEnvironment(macCatalyst)
            target = .mac
            #endif
        }
        overlay = Self.loadOverlay()
        #if DEBUG
        Demo.apply(to: self)
        #endif
    }

    // MARK: - Colours

    func applyPalette(_ palette: Palette) { config.colors = palette.colors }

    func addColor() {
        guard config.colors.count < WallpaperConfig.maxColors else { return }
        let last = config.colors.last ?? .white
        let first = config.colors.first ?? .black
        config.colors.append(last.mix(first, 0.5).lighter(0.25))
    }

    func removeColor(at index: Int) {
        guard config.colors.count > WallpaperConfig.minColors, config.colors.indices.contains(index) else { return }
        config.colors.remove(at: index)
    }

    func randomizeColors() {
        var rng = SplitMix64(seed: UInt64.random(in: 1...UInt64.max))
        let hue = rng.unit()
        let n = max(3, config.colors.count)
        config.colors = (0..<n).map { i in
            let h = (hue + Double(i) * rng.range(0.08, 0.22)).truncatingRemainder(dividingBy: 1)
            let s = rng.range(0.45, 0.9)
            let b = i == 0 ? rng.range(0.12, 0.35) : rng.range(0.6, 1)
            return UIColor(hue: h, saturation: s, brightness: b, alpha: 1).rgb
        }
    }

    func shuffleSeed() { config.seed = UInt64.random(in: 1...UInt64.max) }

    // MARK: - Overlay image

    func setOverlay(data: Data) {
        guard let image = Self.normalised(data) else { return }
        overlay = image
        // A photo with no transparency makes more sense as the background.
        let alpha = image.alphaInfo
        let opaque = alpha == .none || alpha == .noneSkipFirst || alpha == .noneSkipLast
        config.overlay = OverlaySettings()
        config.overlay.placement = opaque ? .background : .logo
        Self.saveOverlay(image)
    }

    func removeOverlay() {
        overlay = nil
        try? FileManager.default.removeItem(at: Self.overlayURL)
    }

    /// Bakes in the photo's orientation and caps its size so exports stay quick. Keeps transparency.
    private static func normalised(_ data: Data) -> CGImage? {
        guard let ui = UIImage(data: data) else { return nil }
        let maxSide: CGFloat = 3000
        let scale = min(1, maxSide / max(ui.size.width, ui.size.height))
        let size = CGSize(width: (ui.size.width * scale).rounded(), height: (ui.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let img = UIGraphicsImageRenderer(size: size, format: format).image { _ in ui.draw(in: CGRect(origin: .zero, size: size)) }
        guard let cg = img.cgImage else { return nil }
        // Keep the source's opacity so a plain photo still reads as opaque.
        if let src = ui.cgImage, [.none, .noneSkipFirst, .noneSkipLast].contains(src.alphaInfo),
           let ctx = CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: 0,
                               space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) {
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            return ctx.makeImage()
        }
        return cg
    }

    private static var overlayURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("overlay.png")
    }

    private static func saveOverlay(_ image: CGImage) {
        guard let dest = CGImageDestinationCreateWithURL(overlayURL as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }

    private static func loadOverlay() -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(overlayURL as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    // MARK: - Saving

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = config
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let data = try? JSONEncoder().encode(snapshot) else { return }
            UserDefaults.standard.set(data, forKey: Keys.config)
        }
    }
}

extension RGB {
    var color: Color { Color(.sRGB, red: r, green: g, blue: b) }
}

extension UIColor {
    var rgb: RGB {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        let srgb = cgColor.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)
        if let c = srgb?.components, c.count >= 3 {
            return RGB(Double(min(1, max(0, c[0]))), Double(min(1, max(0, c[1]))), Double(min(1, max(0, c[2]))))
        }
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return RGB(Double(r), Double(g), Double(b))
    }
}
