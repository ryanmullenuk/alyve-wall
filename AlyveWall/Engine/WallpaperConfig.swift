import CoreGraphics
import Foundation

/// An sRGB colour stored as plain numbers so designs can be saved and passed between threads.
struct RGB: Codable, Hashable, Sendable {
    var r: Double
    var g: Double
    var b: Double

    init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r; self.g = g; self.b = b
    }

    init(hex: UInt32) {
        self.init(Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }

    static let white = RGB(1, 1, 1)
    static let black = RGB(0, 0, 0)

    func cg(_ alpha: Double = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: alpha) }
    func mix(_ o: RGB, _ t: Double) -> RGB { RGB(r + (o.r - r) * t, g + (o.g - g) * t, b + (o.b - b) * t) }
    func scaled(_ k: Double) -> RGB { RGB(min(1, r * k), min(1, g * k), min(1, b * k)) }
    func lighter(_ t: Double) -> RGB { mix(.white, t) }
    var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }
    var hexString: String {
        String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}

enum WallpaperStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case gradient, aurora, lavaLamp, bokeh, starfield, rain, snow, dots, fireflies, clouds, petals, ripples

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gradient: "Gradient"
        case .aurora: "Aurora"
        case .lavaLamp: "Lava Lamp"
        case .bokeh: "Bokeh"
        case .starfield: "Starfield"
        case .rain: "Rain"
        case .snow: "Snow"
        case .dots: "Dots"
        case .fireflies: "Fireflies"
        case .clouds: "Clouds"
        case .petals: "Petals"
        case .ripples: "Ripples"
        }
    }

    var symbol: String {
        switch self {
        case .gradient: "circle.lefthalf.filled"
        case .aurora: "wind"
        case .lavaLamp: "drop.fill"
        case .bokeh: "circle.hexagongrid.fill"
        case .starfield: "sparkles"
        case .rain: "cloud.rain.fill"
        case .snow: "snowflake"
        case .dots: "circle.grid.3x3.fill"
        case .fireflies: "light.min"
        case .clouds: "cloud.fill"
        case .petals: "leaf.fill"
        case .ripples: "water.waves"
        }
    }
}

/// The one PNG or photo a design can carry.
struct OverlaySettings: Codable, Equatable, Sendable {
    enum Placement: String, Codable, CaseIterable, Sendable {
        case logo, background
        var title: String { self == .logo ? "Logo on top" : "Photo behind" }
    }

    var placement: Placement = .logo
    /// Centre of the logo, as fractions of the canvas.
    var x = 0.5
    var y = 0.5
    /// Logo width as a fraction of the canvas's shorter side.
    var scale = 0.4
    var opacity = 1.0
    /// Gently bob the logo up and down once per loop.
    var float = false
    /// Background mode: how strongly the effect's colours wash over the photo.
    var tint = 0.35
}

struct WallpaperConfig: Codable, Equatable, Sendable {
    var style: WallpaperStyle = .gradient
    var colors: [RGB] = Palette.all[0].colors
    var speed = 1.0
    var density = 0.5
    var size = 0.5
    var intensity = 0.75
    /// Length of one seamless loop. Every motion completes a whole number of cycles in it.
    var loopSeconds = 10.0
    var seed: UInt64 = 7
    var overlay = OverlaySettings()

    static let maxColors = 5
    static let minColors = 2
    static let loopChoices: [Double] = [5, 10, 15, 20, 30]

    /// How many whole cycles a motion with `base` cycles per 10 s at speed 1 makes in one loop.
    /// Rounding to a whole number is what makes the end of the video meet its start.
    func cycles(_ base: Double) -> Int {
        max(1, Int((base * speed * loopSeconds / 10).rounded()))
    }
}

struct Palette: Identifiable, Sendable {
    let name: String
    let colors: [RGB]
    var id: String { name }

    static let all: [Palette] = [
        Palette(name: "Dusk", colors: [RGB(hex: 0x2B1055), RGB(hex: 0x7597DE), RGB(hex: 0xF27BBD), RGB(hex: 0xFFB36B)]),
        Palette(name: "Ocean", colors: [RGB(hex: 0x021B3A), RGB(hex: 0x0A6C9E), RGB(hex: 0x2EC4B6), RGB(hex: 0xA8F0E8)]),
        Palette(name: "Aurora", colors: [RGB(hex: 0x050A1F), RGB(hex: 0x1DE9B6), RGB(hex: 0x7C4DFF), RGB(hex: 0x00B0FF)]),
        Palette(name: "Candy", colors: [RGB(hex: 0xFF61D2), RGB(hex: 0xFE9090), RGB(hex: 0xFFD86F), RGB(hex: 0x8EC5FC), RGB(hex: 0xE0C3FC)]),
        Palette(name: "Ember", colors: [RGB(hex: 0x1A0505), RGB(hex: 0xC0392B), RGB(hex: 0xFF7A18), RGB(hex: 0xFFD166)]),
        Palette(name: "Forest", colors: [RGB(hex: 0x0B1F16), RGB(hex: 0x2D6A4F), RGB(hex: 0x95D5B2), RGB(hex: 0xD8F3DC)]),
        Palette(name: "Peach", colors: [RGB(hex: 0xFFE5D9), RGB(hex: 0xFFB4A2), RGB(hex: 0xE5989B), RGB(hex: 0xB5838D)]),
        Palette(name: "Midnight", colors: [RGB(hex: 0x03001C), RGB(hex: 0x301E67), RGB(hex: 0x5B8FB9), RGB(hex: 0xB6EADA)]),
        Palette(name: "Citrus", colors: [RGB(hex: 0xF9F871), RGB(hex: 0xA5E65A), RGB(hex: 0x29B57A), RGB(hex: 0x00727A)]),
        Palette(name: "Mono", colors: [RGB(hex: 0x0D0D0F), RGB(hex: 0x3A3A40), RGB(hex: 0x9A9AA3), RGB(hex: 0xF2F2F5)]),
        Palette(name: "Sakura", colors: [RGB(hex: 0x2A1B3D), RGB(hex: 0x8E4162), RGB(hex: 0xF7A9C4), RGB(hex: 0xFFF0F5)]),
        Palette(name: "Neon", colors: [RGB(hex: 0x0F0026), RGB(hex: 0xFF00A8), RGB(hex: 0x00F0FF), RGB(hex: 0x7B00FF), RGB(hex: 0xFFE600)]),
    ]
}

/// Small deterministic generator so the same seed always draws the same particles.
struct SplitMix64: Sendable {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    mutating func range(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * unit() }
    mutating func int(_ lo: Int, _ hi: Int) -> Int { lo + Int(next() % UInt64(hi - lo + 1)) }
}
