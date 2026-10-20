import SwiftUI

@main
struct AlyveWallApp: App {
    @State private var model = EditorModel()
    @State private var store = PremiumStore()

    var body: some Scene {
        WindowGroup {
            EditorView()
                .environment(model)
                .environment(store)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                #if DEBUG
                .task { await SelfTest.runIfRequested(model: model) }
                #endif
        }
    }
}

#if DEBUG
/// `-selfTest` launch argument: exports an MP4 and a Live Photo and saves both to Photos,
/// printing the outcome, so the export path can be checked without tapping through the UI.
enum SelfTest {
    @MainActor
    static func runIfRequested(model: EditorModel) async {
        guard ProcessInfo.processInfo.arguments.contains("-selfTest") else { return }
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
