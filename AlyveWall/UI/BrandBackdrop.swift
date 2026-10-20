import SwiftUI

/// The brand backdrop as a SwiftUI background: soft glows (drawn small and scaled up, since
/// they're blurry anyway) under a crisp LED dot grid drawn at screen resolution.
struct BrandBackdrop: View {
    /// Moves the glows slowly when true.
    var animated = false
    /// Darkens the backdrop so content on top stays readable.
    var dim: Double = 0

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if animated {
                    TimelineView(.animation(minimumInterval: 1.0 / 30)) { tl in
                        let t = tl.date.timeIntervalSinceReferenceDate
                        glows(size: geo.size, drift: (t / 14).truncatingRemainder(dividingBy: 1))
                    }
                } else {
                    glows(size: geo.size, drift: 0)
                }
                Canvas { ctx, size in
                    let pitch = max(3, min(size.width, size.height) / 150)
                    let line = max(1 / displayScale, pitch * 0.32)
                    var path = Path()
                    var v: CGFloat = 0
                    while v < size.width { path.addRect(CGRect(x: v, y: 0, width: line, height: size.height)); v += pitch }
                    v = 0
                    while v < size.height { path.addRect(CGRect(x: 0, y: v, width: size.width, height: line)); v += pitch }
                    ctx.fill(path, with: .color(.black.opacity(0.55)))
                }
                if dim > 0 { Color.black.opacity(dim) }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func glows(size: CGSize, drift: Double) -> some View {
        Group {
            if let img = BackdropCache.shared.image(aspect: size.width / max(1, size.height), drift: drift) {
                Image(decorative: img, scale: 1).resizable().interpolation(.high)
            } else {
                Color(red: 0.01, green: 0.02, blue: 0.1)
            }
        }
    }
}

@MainActor
final class BackdropCache {
    static let shared = BackdropCache()
    private var still: (Double, CGImage)?

    func image(aspect: Double, drift: Double) -> CGImage? {
        if drift == 0, let s = still, abs(s.0 - aspect) < 0.01 { return s.1 }
        let h = 420.0
        let w = max(40, (h * aspect).rounded())
        guard let ctx = CGContext(data: nil, width: Int(w), height: Int(h), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        Brand.drawBackdrop(ctx, width: w, height: h, drift: drift, grid: false)
        let img = ctx.makeImage()
        if drift == 0, let img { still = (aspect, img) }
        return img
    }
}

/// Opening animation: the backdrop drifts into focus, the ribbon A and the wordmark resolve out
/// of a blur, then the whole thing dissolves into the editor.
struct SplashView: View {
    /// Called once the title has landed, so the editor can be built behind the splash without
    /// stealing frames from the opening animation.
    var onReveal: () -> Void = {}
    var onFinish: () -> Void

    @State private var focused = false
    @State private var logoIn = false
    @State private var titleIn = false
    @State private var leaving = false

    var body: some View {
        ZStack {
            Brand.base.color.ignoresSafeArea()
            BrandBackdrop(animated: true)
                .scaleEffect(focused ? 1 : 1.25)
                .blur(radius: focused ? 0 : 40)
                .ignoresSafeArea()
            VStack(spacing: 26) {
                Image("LogoA")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 150, height: 150)
                    .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
                    .scaleEffect(logoIn ? 1 : 0.6)
                    .blur(radius: logoIn ? 0 : 18)
                    .opacity(logoIn ? 1 : 0)
                VStack(spacing: 8) {
                    Wordmark(size: 30, spread: titleIn ? 0 : 14)
                    Text("Wallpapers that come alive")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .blur(radius: titleIn ? 0 : 12)
                .opacity(titleIn ? 1 : 0)
                .offset(y: titleIn ? 0 : 14)
            }
            .scaleEffect(leaving ? 1.12 : 1)
        }
        .blur(radius: leaving ? 24 : 0)
        .opacity(leaving ? 0 : 1)
        .task {
            withAnimation(.easeOut(duration: 1.3)) { focused = true }
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.spring(response: 0.8, dampingFraction: 0.75)) { logoIn = true }
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(.easeOut(duration: 0.8)) { titleIn = true }
            try? await Task.sleep(for: .milliseconds(700))
            onReveal()
            try? await Task.sleep(for: .milliseconds(700))
            withAnimation(.easeIn(duration: 0.55)) { leaving = true }
            try? await Task.sleep(for: .milliseconds(550))
            onFinish()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("ALYVE WALL")
    }
}
