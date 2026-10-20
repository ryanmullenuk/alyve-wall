import SwiftUI

/// Keeps one renderer alive between frames and rebuilds it only when the design or size changes.
@MainActor
final class RendererCache {
    private var renderer: WallpaperRenderer?
    private var key: (WallpaperConfig, Int, Int, ObjectIdentifier?, Bool)?

    func image(config: WallpaperConfig, overlay: CGImage?, width: Int, height: Int, watermark: Bool, phase: Double) -> CGImage? {
        guard width > 8, height > 8 else { return nil }
        let id = overlay.map { ObjectIdentifier($0) }
        if let k = key, k.0 == config, k.1 == width, k.2 == height, k.3 == id, k.4 == watermark, let renderer {
            return renderer.makeImage(phase: phase)
        }
        let r = WallpaperRenderer(config: config, width: width, height: height, overlay: overlay, watermark: watermark)
        renderer = r
        key = (config, width, height, id, watermark)
        return r.makeImage(phase: phase)
    }
}

/// The live, animated wallpaper inside an iPhone or Mac frame. Drag to move the logo, pinch to resize it.
struct LivePreview: View {
    @Environment(EditorModel.self) private var model
    @Environment(PremiumStore.self) private var store
    @Environment(\.displayScale) private var displayScale
    @State private var cache = RendererCache()
    @State private var pinchStart: Double?

    var body: some View {
        GeometryReader { geo in
            let size = fitted(in: geo.size)
            frame(size: size)
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func fitted(in space: CGSize) -> CGSize {
        let aspect = model.target.aspect
        var w = space.width
        var h = w / aspect
        if h > space.height {
            h = space.height
            w = h * aspect
        }
        return CGSize(width: floor(w), height: floor(h))
    }

    private func frame(size: CGSize) -> some View {
        let corner = model.target == .iphone ? size.width * 0.13 : size.width * 0.02
        return TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !model.isPlaying)) { timeline in
            let loop = model.config.loopSeconds
            let t = timeline.date.timeIntervalSinceReferenceDate
            let phase = t.truncatingRemainder(dividingBy: loop) / loop
            let scale = min(displayScale, 2)
            if let img = cache.image(config: model.config, overlay: model.overlay,
                                     width: Int(size.width * scale), height: Int(size.height * scale),
                                     watermark: !store.isPremium, phase: phase) {
                Image(decorative: img, scale: scale)
                    .resizable()
                    .interpolation(.high)
            } else {
                Color.black
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay { if model.showLockScreen { DeviceChrome(target: model.target, size: size) } }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: model.target == .iphone ? 3 : 1.5)
        )
        .shadow(color: .black.opacity(0.6), radius: 20, y: 8)
        .contentShape(Rectangle())
        .gesture(dragLogo(size: size))
        .simultaneousGesture(pinchLogo)
        .onTapGesture(count: 2) { model.isPlaying.toggle() }
        .accessibilityLabel("Wallpaper preview, \(model.config.style.title)")
    }

    private var logoEditable: Bool { model.overlay != nil && model.config.overlay.placement == .logo }

    private func dragLogo(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard logoEditable else { return }
                model.config.overlay.x = min(1, max(0, value.location.x / size.width))
                model.config.overlay.y = min(1, max(0, value.location.y / size.height))
            }
    }

    private var pinchLogo: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard logoEditable else { return }
                let start = pinchStart ?? model.config.overlay.scale
                pinchStart = start
                model.config.overlay.scale = min(1.2, max(0.05, start * value.magnification))
            }
            .onEnded { _ in pinchStart = nil }
    }
}

/// A faint Lock Screen clock or Mac menu bar so you can judge the design in place.
private struct DeviceChrome: View {
    let target: DeviceTarget
    let size: CGSize

    var body: some View {
        if target == .iphone {
            VStack(spacing: 0) {
                Capsule().fill(.black).frame(width: size.width * 0.3, height: size.width * 0.085)
                    .padding(.top, size.width * 0.03)
                Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.system(size: size.width * 0.045, weight: .semibold))
                    .padding(.top, size.width * 0.06)
                Text("9:41")
                    .font(.system(size: size.width * 0.24, weight: .bold, design: .rounded))
                Spacer()
                Capsule().fill(.white.opacity(0.8)).frame(width: size.width * 0.35, height: 4)
                    .padding(.bottom, size.width * 0.025)
            }
            .foregroundStyle(.white.opacity(0.85))
            .shadow(color: .black.opacity(0.2), radius: 6)
            .allowsHitTesting(false)
        } else {
            VStack(spacing: 0) {
                HStack(spacing: size.width * 0.02) {
                    Image(systemName: "apple.logo")
                    Text("Finder").fontWeight(.bold)
                    Text("File")
                    Text("Edit")
                    Spacer()
                    Text("Mon 9:41")
                }
                .font(.system(size: max(6, size.width * 0.018)))
                .padding(.horizontal, size.width * 0.015)
                .frame(height: size.width * 0.03)
                .background(.black.opacity(0.18))
                Spacer()
                RoundedRectangle(cornerRadius: size.width * 0.012)
                    .fill(.white.opacity(0.22))
                    .frame(width: size.width * 0.42, height: size.width * 0.045)
                    .padding(.bottom, size.width * 0.012)
            }
            .foregroundStyle(.white.opacity(0.9))
            .allowsHitTesting(false)
        }
    }
}
