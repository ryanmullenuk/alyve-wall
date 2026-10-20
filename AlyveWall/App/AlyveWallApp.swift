import SwiftUI

@main
struct AlyveWallApp: App {
    @State private var model = EditorModel()
    @State private var store = PremiumStore()
    @State private var showSplash = true
    @State private var editorReady = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                if editorReady { EditorView() }
                if showSplash {
                    SplashView(onReveal: { editorReady = true }) { showSplash = false }
                        .transition(.identity)
                        .zIndex(1)
                }
            }
            .environment(model)
            .environment(store)
            .preferredColorScheme(.dark)
            .tint(Theme.accent)
            .onAppear {
                #if DEBUG
                if Demo.flag("noSplash") { showSplash = false; editorReady = true }
                #endif
                #if targetEnvironment(macCatalyst)
                for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                    scene.sizeRestrictions?.minimumSize = CGSize(width: 900, height: 620)
                    #if DEBUG
                    if let w = Demo.string("demoWindow")?.split(separator: "x").compactMap({ Double($0) }), w.count == 2 {
                        scene.sizeRestrictions?.minimumSize = CGSize(width: w[0], height: w[1])
                        scene.sizeRestrictions?.maximumSize = CGSize(width: w[0], height: w[1])
                    }
                    #endif
                }
                #endif
            }
            #if DEBUG
            .task { await SelfTest.runIfRequested(model: model) }
            .task { await Demo.snapshotIfRequested() }
            #endif
        }
    }
}

#if DEBUG
/// Launch arguments for screenshots and testing, e.g. `-demoStyle aurora -demoTab colours -noSplash YES`.
/// They arrive through the arguments domain of UserDefaults.
enum Demo {
    static func string(_ key: String) -> String? { UserDefaults.standard.string(forKey: key) }
    static func flag(_ key: String) -> Bool { UserDefaults.standard.bool(forKey: key) }

    @MainActor
    static func apply(to model: EditorModel) {
        if let s = string("demoStyle").flatMap(WallpaperStyle.init(rawValue:)) { model.config.style = s }
        if let name = string("demoPalette"), let p = Palette.all.first(where: { $0.name == name }) { model.config.colors = p.colors }
        if let t = string("demoTarget").flatMap(DeviceTarget.init(rawValue:)) { model.target = t }
        if string("demoGrid") != nil { model.config.dotGrid = flag("demoGrid") }
        if let d = string("demoDensity").flatMap(Double.init) { model.config.density = d }
        if flag("demoLogo"), let logo = UIImage(named: "LogoA")?.pngData() {
            model.setOverlay(data: logo)
            model.config.overlay.scale = 0.42
            model.config.overlay.y = 0.55
        } else if string("demoLogo") != nil {
            model.removeOverlay()
        }
    }
}

extension Demo {
    /// `-demoSnapshot name.png`: after the UI settles, renders the app's own window to a PNG in
    /// the app's temporary folder (used for Mac App Store screenshots).
    @MainActor
    static func snapshotIfRequested() async {
        guard let name = string("demoSnapshot") else { return }
        try? await Task.sleep(for: .seconds(Double(string("demoSnapshotDelay") ?? "5") ?? 5))
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        guard let window = windows.first(where: \.isKeyWindow) ?? windows.first else { return }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        var sheet = window.rootViewController?.presentedViewController
        while let next = sheet?.presentedViewController { sheet = next }
        // Mac sheets are separate system windows, so capture just the sheet; the store artwork
        // tool lays it over a shot of the main window.
        #if targetEnvironment(macCatalyst)
        let target: UIView = sheet?.view ?? window
        #else
        let target: UIView = window
        #endif
        let image = UIGraphicsImageRenderer(bounds: target.bounds, format: format).image { _ in
            target.drawHierarchy(in: target.bounds, afterScreenUpdates: true)
        }
        let url = name.hasPrefix("/") ? URL(fileURLWithPath: name) : URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
        try? image.pngData()?.write(to: url)
        print("SNAPSHOT", url.path)
    }
}

/// `-selfTest YES`: exports an MP4 and a Live Photo and saves both to Photos, printing the
/// outcome, so the export path can be checked without tapping through the UI.
enum SelfTest {
    @MainActor
    static func runIfRequested(model: EditorModel) async {
        guard Demo.flag("selfTest") || ProcessInfo.processInfo.arguments.contains("-selfTest") else { return }
        var config = model.config
        config.style = .aurora
        config.loopSeconds = 5
        let size = ExportSize.iphone[1]
        do {
            let mp4 = try await Task.detached {
                try Exporter.exportMP4(config: config, overlay: SendableImage(image: nil), size: size, fps: 30, watermark: true,
                                       control: ExportControl()) { _ in }
            }.value
            try await PhotoSaver.saveVideo(mp4)
            print("SELFTEST mp4 saved", mp4.lastPathComponent)
            let live = try await Task.detached {
                try Exporter.exportLivePhoto(config: config, overlay: SendableImage(image: nil), size: ExportSize.livePhotoPremium,
                                             watermark: false, control: ExportControl()) { _ in }
            }.value
            try await PhotoSaver.saveLivePhoto(photo: live.photo, video: live.video)
            print("SELFTEST live photo saved")
        } catch {
            print("SELFTEST failed:", error)
        }
    }
}
#endif
