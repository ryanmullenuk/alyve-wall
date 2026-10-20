import SwiftUI

/// Runs one export off the main thread and publishes its progress.
@MainActor
@Observable
final class ExportJob {
    enum Result {
        case video(URL)
        case live(photo: URL, video: URL)
        case still(URL)

        var shareURL: URL {
            switch self {
            case .video(let u), .still(let u): u
            case .live(_, let v): v
            }
        }
    }

    enum State {
        case idle
        case working(Double)
        case done(Result)
        case failed(String)
    }

    var state: State = .idle
    var saveMessage: String?
    var isSaving = false
    private var control: ExportControl?

    var isWorking: Bool { if case .working = state { true } else { false } }

    func start(format: ExportSheet.Format, config: WallpaperConfig, overlay: CGImage?, size: ExportSize, fps: Int, watermark: Bool) {
        let control = ExportControl()
        self.control = control
        state = .working(0)
        saveMessage = nil
        let image = SendableImage(image: overlay)
        let report: @Sendable (Double) -> Void = { [weak self] p in
            Task { @MainActor in
                guard let self, case .working = self.state else { return }
                self.state = .working(p)
            }
        }
        Task {
            do {
                let result: Result = try await Task.detached(priority: .userInitiated) {
                    switch format {
                    case .video:
                        return .video(try Exporter.exportMP4(config: config, overlay: image, size: size, fps: fps,
                                                             watermark: watermark, control: control, progress: report))
                    case .live:
                        let r = try Exporter.exportLivePhoto(config: config, overlay: image, size: size, watermark: watermark,
                                                             control: control, progress: report)
                        return .live(photo: r.photo, video: r.video)
                    case .still:
                        return .still(try Exporter.exportStill(config: config, overlay: image, size: size, phase: 0.25, watermark: watermark))
                    }
                }.value
                state = .done(result)
                if case .live = result { await save() }
            } catch ExportError.cancelled {
                state = .idle
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() { control?.cancel() }

    func save() async {
        guard case .done(let result) = state else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            switch result {
            case .video(let u): try await PhotoSaver.saveVideo(u)
            case .still(let u): try await PhotoSaver.saveImage(u)
            case .live(let p, let v): try await PhotoSaver.saveLivePhoto(photo: p, video: v)
            }
            saveMessage = "Saved to Photos"
        } catch {
            saveMessage = error.localizedDescription
        }
    }
}

struct ExportSheet: View {
    enum Format: String, CaseIterable, Identifiable {
        case video = "MP4 Video", live = "Live Photo", still = "Still"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .video: "film.fill"
            case .live: "livephoto"
            case .still: "photo.fill"
            }
        }
    }

    @Environment(EditorModel.self) private var model
    @Environment(PremiumStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var job = ExportJob()
    @State private var format: Format = .video
    @State private var target: DeviceTarget = .iphone
    @State private var size: ExportSize = ExportSize.iphone[0]
    @State private var fps = 30
    @State private var showPremium = false
    @State private var showMover = false

    static var isMac: Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        false
        #endif
    }

    private var premium: Bool { store.isPremium }

    var body: some View {
        NavigationStack {
            ZStack {
                BrandBackdrop(dim: 0.55)
                switch job.state {
                case .idle, .failed: options
                case .working(let p): working(p)
                case .done(let result): done(result)
                }
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(job.isWorking ? "Cancel" : "Close") {
                        if job.isWorking { job.cancel() } else { dismiss() }
                    }
                }
            }
        }
        .presentationDetents([.large])
        #if targetEnvironment(macCatalyst)
        .frame(minWidth: 560, idealWidth: 600, minHeight: 760, idealHeight: 820)
        #endif
        .interactiveDismissDisabled(job.isWorking)
        .sheet(isPresented: $showPremium) { PremiumView().environment(store) }
        .onAppear {
            target = model.target
            size = bestSize(for: target)
        }
        .onChange(of: store.isPremium) { _, _ in size = bestSize(for: target) }
    }

    private func bestSize(for target: DeviceTarget) -> ExportSize {
        let list = ExportSize.sizes(for: target)
        return premium ? list[1] : list[0]
    }

    // MARK: Options

    private var options: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Picker("Format", selection: $format) {
                    ForEach(Format.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
                }
                .pickerStyle(.segmented)

                if format == .live {
                    liveOptions
                } else {
                    sizeOptions
                }

                if format == .video {
                    section("Frame rate") {
                        HStack(spacing: 10) {
                            ForEach([30, 60], id: \.self) { f in
                                choice(title: "\(f) fps", subtitle: f == 30 ? "Smaller file" : "Silky smooth",
                                       selected: fps == f, locked: f == 60 && !premium) { fps = f }
                            }
                        }
                    }
                    Label("One seamless \(Int(model.config.loopSeconds))-second loop. Change it in Motion.", systemImage: "repeat")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                if !premium { upsell }

                if case .failed(let message) = job.state {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(.orange)
                }

                Button {
                    let chosen = format == .live ? (premium ? ExportSize.livePhotoPremium : ExportSize.livePhotoFree) : size
                    job.start(format: format, config: model.config, overlay: model.overlay, size: chosen,
                              fps: premium ? fps : 30, watermark: !premium)
                } label: {
                    Text(format == .live ? "Create Live Photo" : format == .video ? "Create video" : "Create image")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Theme.glow, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .foregroundStyle(.white)
                }
            }
            .padding(20)
        }
    }

    private var sizeOptions: some View {
        VStack(alignment: .leading, spacing: 22) {
            section("Device") {
                Picker("Device", selection: $target) {
                    ForEach(DeviceTarget.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: target) { _, t in size = bestSize(for: t) }
            }
            section("Size") {
                VStack(spacing: 8) {
                    ForEach(ExportSize.sizes(for: target)) { s in
                        choice(title: s.name, subtitle: s.label, selected: size == s, locked: s.premium && !premium) { size = s }
                    }
                }
            }
        }
    }

    private var liveOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            section("Live Photo for your Lock Screen") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(premium ? "Full HD 1080 × 1920, no watermark." : "720 × 1280 with a small watermark. Premium makes it Full HD with no watermark.")
                    Text("It's saved straight to Photos. Then go to Settings › Wallpaper › Add New Wallpaper › Photos, choose it and make sure the Live Photo button is on.")
                        .foregroundStyle(.secondary)
                }
                .font(.footnote)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private var upsell: some View {
        Button {
            showPremium = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "crown.fill").font(.title2).foregroundStyle(Theme.gold)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Go Premium, \(store.price) once").font(.subheadline.weight(.bold))
                    Text("No watermark, up to 5K Mac and native iPhone sizes, 60 fps.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.gold, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary).tracking(1)
            content()
        }
    }

    private func choice(title: String, subtitle: String, selected: Bool, locked: Bool, action: @escaping () -> Void) -> some View {
        Button {
            if locked { showPremium = true } else { action() }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(subtitle).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Spacer()
                if locked {
                    PremiumBadge()
                } else if selected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? Color.white.opacity(0.12) : Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(selected ? Theme.accent : .clear, lineWidth: 1.5))
            .opacity(locked ? 0.6 : 1)
        }
        .buttonStyle(.plain)
    }

    // MARK: Progress and result

    private func working(_ progress: Double) -> some View {
        VStack(spacing: 18) {
            ProgressView(value: progress)
                .progressViewStyle(.circular)
                .scaleEffect(1.6)
            Text(format == .live ? "Making your Live Photo…" : format == .video ? "Rendering your video…" : "Rendering…")
                .font(.headline)
            ProgressView(value: progress).frame(width: 220)
            Text("\(Int(progress * 100))%").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    private func done(_ result: ExportJob.Result) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 54)).foregroundStyle(Theme.glow)
            Text(doneTitle(result)).font(.title3.weight(.bold))
            Text(doneHint(result))
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            VStack(spacing: 10) {
                Button {
                    Task { await job.save() }
                } label: {
                    Label(job.saveMessage == "Saved to Photos" ? "Saved to Photos" : "Save to Photos",
                          systemImage: job.saveMessage == "Saved to Photos" ? "checkmark" : "photo.on.rectangle")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Theme.glow, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(.white)
                }
                .disabled(job.isSaving)

                if case .live = result {
                    EmptyView()
                } else {
                    Button {
                        showMover = true
                    } label: {
                        Label(Self.isMac ? "Save to a folder…" : "Save to Files", systemImage: "folder")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .fileMover(isPresented: $showMover, file: result.shareURL) { outcome in
                        if case .success = outcome { job.saveMessage = "Saved to Files" }
                    }
                    ShareLink(item: result.shareURL) {
                        Label(Self.isMac ? "Share…" : "Share or AirDrop to Mac", systemImage: "square.and.arrow.up")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                Button("Export another") { job.state = .idle }
                    .padding(.top, 4)
            }
            .padding(.horizontal, 24)

            if let message = job.saveMessage, message != "Saved to Photos" {
                let ok = message == "Saved to Files"
                Text(message).font(.footnote).foregroundStyle(ok ? Color.green : Color.orange).multilineTextAlignment(.center).padding(.horizontal, 24)
            }
        }
    }

    private func doneTitle(_ result: ExportJob.Result) -> String {
        switch result {
        case .video: "Your video is ready"
        case .live: job.saveMessage == "Saved to Photos" ? "Live Photo saved" : "Your Live Photo is ready"
        case .still: "Your image is ready"
        }
    }

    private func doneHint(_ result: ExportJob.Result) -> String {
        switch result {
        case .video:
            target == .mac
                ? "AirDrop it to your Mac and set it with your favourite video-wallpaper app. It loops seamlessly."
                : "Save it to Photos or Files. It loops seamlessly."
        case .live:
            "Settings › Wallpaper › Add New Wallpaper › Photos. Pick it, keep the Live Photo button on, and touch and hold the Lock Screen to see it move."
        case .still:
            "Save it to Photos to use as a still wallpaper."
        }
    }
}
