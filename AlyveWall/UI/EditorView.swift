import PhotosUI
import SwiftUI

struct EditorView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case style = "Style", colours = "Colours", image = "Image", motion = "Motion"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .style: "square.grid.2x2.fill"
            case .colours: "paintpalette.fill"
            case .image: "photo.fill"
            case .motion: "slider.horizontal.3"
            }
        }
    }

    @Environment(EditorModel.self) private var model
    @Environment(PremiumStore.self) private var store
    @State private var tab: Tab = .style
    @State private var showExport = false
    @State private var showPremium = false

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > 820 && geo.size.width > geo.size.height * 1.05
            ZStack {
                BrandBackdrop(dim: 0.45)
                if wide {
                    HStack(spacing: 0) {
                        VStack(spacing: 12) {
                            header
                            LivePreview()
                                .padding(24)
                                .frame(maxHeight: .infinity)
                        }
                        VStack(spacing: 12) {
                            tabBar
                            panel.frame(maxHeight: .infinity)
                            exportButton
                        }
                        .frame(width: min(440, geo.size.width * 0.4))
                        .padding(.vertical, 12)
                        .background(Color.black.opacity(0.35))
                    }
                } else {
                    VStack(spacing: 12) {
                        header
                        LivePreview()
                            .padding(.horizontal, 20)
                            .frame(maxHeight: .infinity)
                        tabBar
                        panel.frame(height: 250)
                        exportButton
                    }
                    .padding(.top, 4)
                }
            }
        }
        .sheet(isPresented: $showExport) { ExportSheet().environment(model).environment(store) }
        .sheet(isPresented: $showPremium) { PremiumView().environment(store) }
        #if DEBUG
        .task {
            if let t = Demo.string("demoTab").flatMap({ Tab(rawValue: $0.capitalized) }) { tab = t }
            guard let sheet = Demo.string("demoSheet") else { return }
            try? await Task.sleep(for: .seconds(1))
            if sheet == "export" { showExport = true }
            if sheet == "premium" { showPremium = true }
        }
        #endif
    }

    private var panel: some View {
        ScrollView {
            Group {
                switch tab {
                case .style: StylePanel()
                case .colours: ColoursPanel()
                case .image: ImagePanel()
                case .motion: MotionPanel()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .scrollIndicators(.hidden)
    }

    private var header: some View {
        @Bindable var model = model
        return HStack(spacing: 10) {
            Wordmark(size: 17)
            Spacer()
            Picker("Device", selection: $model.target) {
                ForEach(DeviceTarget.allCases) { t in Image(systemName: t.symbol).tag(t) }
            }
            .pickerStyle(.segmented)
            .frame(width: 96)
            Button {
                showPremium = true
            } label: {
                Image(systemName: store.isPremium ? "crown.fill" : "crown")
                    .font(.headline)
                    .foregroundStyle(Theme.gold)
                    .frame(width: 36, height: 32)
            }
            .accessibilityLabel(store.isPremium ? "Premium" : "Get Premium")
        }
        .padding(.horizontal, 16)
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(Tab.allCases) { t in
                Button {
                    withAnimation(.snappy) { tab = t }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: t.symbol).font(.system(size: 15, weight: .semibold))
                        Text(t.rawValue).font(.caption2.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        if tab == t {
                            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.12))
                        }
                    }
                    .foregroundStyle(tab == t ? .white : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Theme.card))
        .padding(.horizontal, 16)
    }

    private var exportButton: some View {
        Button {
            showExport = true
        } label: {
            HStack {
                Image(systemName: "square.and.arrow.down.fill")
                Text("Export wallpaper")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Theme.glow, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }
}

// MARK: - Style

struct StylePanel: View {
    @Environment(EditorModel.self) private var model
    @State private var thumbs = ThumbnailCache()

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
            ForEach(WallpaperStyle.allCases) { style in
                let selected = model.config.style == style
                Button {
                    withAnimation(.snappy) { model.config.style = style }
                } label: {
                    VStack(spacing: 5) {
                        Group {
                            if let img = thumbs.image(style: style, colors: model.config.colors) {
                                Image(decorative: img, scale: 2).resizable()
                            } else {
                                Color.black
                            }
                        }
                        .aspectRatio(0.62, contentMode: .fit)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: style.symbol)
                                .font(.system(size: 11, weight: .bold))
                                .padding(5)
                                .foregroundStyle(.white.opacity(0.9))
                                .shadow(radius: 2)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(selected ? AnyShapeStyle(Theme.glow) : AnyShapeStyle(Theme.stroke), lineWidth: selected ? 3 : 1)
                        )
                        Text(style.title)
                            .font(.caption.weight(selected ? .bold : .medium))
                            .foregroundStyle(selected ? .white : .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.top, 4)
    }
}

@MainActor
final class ThumbnailCache {
    private var images: [String: CGImage] = [:]

    func image(style: WallpaperStyle, colors: [RGB]) -> CGImage? {
        let key = style.rawValue + colors.map(\.hexString).joined()
        if let img = images[key] { return img }
        if images.count > 120 { images.removeAll() }
        var c = WallpaperConfig()
        c.style = style
        c.colors = colors
        c.density = 0.55
        let img = WallpaperRenderer(config: c, width: 150, height: 242, overlay: nil, watermark: false).makeImage(phase: 0.3)
        images[key] = img
        return img
    }
}

// MARK: - Colours

struct ColoursPanel: View {
    @Environment(EditorModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Palette.all) { palette in
                        Button {
                            withAnimation { model.applyPalette(palette) }
                        } label: {
                            VStack(spacing: 4) {
                                LinearGradient(colors: palette.colors.map(\.color), startPoint: .topLeading, endPoint: .bottomTrailing)
                                    .frame(width: 58, height: 40)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(
                                        model.config.colors == palette.colors ? Color.white : Theme.stroke,
                                        lineWidth: model.config.colors == palette.colors ? 2 : 1))
                                Text(palette.name).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)

            HStack {
                Text("Your colours").font(.subheadline.weight(.semibold))
                Text("\(model.config.colors.count) of \(WallpaperConfig.maxColors)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    withAnimation { model.randomizeColors() }
                } label: {
                    Label("Surprise me", systemImage: "dice.fill").font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            HStack(spacing: 10) {
                ForEach(Array(model.config.colors.enumerated()), id: \.offset) { index, _ in
                    swatch(index)
                }
                if model.config.colors.count < WallpaperConfig.maxColors {
                    Button {
                        withAnimation { model.addColor() }
                    } label: {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                            .foregroundStyle(.secondary)
                            .frame(height: 64)
                            .overlay(Image(systemName: "plus").font(.title3.weight(.semibold)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add colour")
                }
            }
            Text("Tap a colour to change it. Long-press to remove it.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private func swatch(_ index: Int) -> some View {
        let binding = Binding<Color>(
            get: { model.config.colors.indices.contains(index) ? model.config.colors[index].color : .black },
            set: { new in
                guard model.config.colors.indices.contains(index) else { return }
                model.config.colors[index] = UIColor(new).rgb
            }
        )
        return ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(binding.wrappedValue)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.stroke))
            // The system picker is stretched invisibly over the swatch so the whole tile opens it.
            ColorPicker("Colour \(index + 1)", selection: binding, supportsOpacity: false)
                .labelsHidden()
                .scaleEffect(3)
                .opacity(0.015)
        }
        .frame(height: 64)
        .clipped()
        .contextMenu {
            if model.config.colors.count > WallpaperConfig.minColors {
                Button(role: .destructive) {
                    withAnimation { model.removeColor(at: index) }
                } label: { Label("Remove colour", systemImage: "trash") }
            }
        }
    }
}

// MARK: - Image

struct ImagePanel: View {
    @Environment(EditorModel.self) private var model
    @State private var item: PhotosPickerItem?
    @State private var loading = false

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                if let img = model.overlay {
                    Image(decorative: img, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 56, height: 56)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                PhotosPicker(selection: $item, matching: .images, photoLibrary: .shared()) {
                    Label(model.overlay == nil ? "Add a PNG logo or photo" : "Replace image", systemImage: "photo.badge.plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                if model.overlay != nil {
                    Button(role: .destructive) {
                        withAnimation { model.removeOverlay() }
                    } label: {
                        Image(systemName: "trash").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Remove image")
                }
            }
            if loading { ProgressView().frame(maxWidth: .infinity) }

            if model.overlay != nil {
                Picker("Placement", selection: $model.config.overlay.placement) {
                    ForEach(OverlaySettings.Placement.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                if model.config.overlay.placement == .logo {
                    SliderRow(title: "Size", value: $model.config.overlay.scale, range: 0.05...1.2)
                    SliderRow(title: "Opacity", value: $model.config.overlay.opacity, range: 0.1...1)
                    Toggle("Gentle float", isOn: $model.config.overlay.float).font(.subheadline.weight(.medium))
                    HStack {
                        Text("Drag the logo on the preview to move it, pinch to resize.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Centre") {
                            withAnimation { model.config.overlay.x = 0.5; model.config.overlay.y = 0.5 }
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                    }
                } else {
                    SliderRow(title: "Effect colour wash", value: $model.config.overlay.tint, range: 0...1)
                    Text("Your photo fills the screen and the animated effect plays over it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Add one image: a transparent PNG logo sits on top of the animation, or use a photo as the background.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
        .onChange(of: item) { _, newItem in
            guard let newItem else { return }
            loading = true
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    withAnimation { model.setOverlay(data: data) }
                }
                loading = false
                item = nil
            }
        }
    }
}

// MARK: - Motion

struct MotionPanel: View {
    @Environment(EditorModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 12) {
            SliderRow(title: "Speed", value: $model.config.speed, range: 0.25...3) { String(format: "%.2g×", $0) }
            SliderRow(title: "Amount", value: $model.config.density)
            SliderRow(title: "Size", value: $model.config.size)
            SliderRow(title: "Glow", value: $model.config.intensity)
            Toggle(isOn: $model.config.dotGrid) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Dot screen").font(.subheadline.weight(.medium))
                    Text("A fine LED dot grid over the whole wallpaper").font(.caption).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Loop length").font(.subheadline.weight(.medium))
                Picker("Loop length", selection: $model.config.loopSeconds) {
                    ForEach(WallpaperConfig.loopChoices, id: \.self) { Text("\(Int($0))s").tag($0) }
                }
                .pickerStyle(.segmented)
            }
            HStack {
                Button {
                    withAnimation { model.shuffleSeed() }
                } label: { Label("Shuffle layout", systemImage: "shuffle") }
                Spacer()
                Toggle(isOn: $model.showLockScreen) { Text("Clock overlay").font(.subheadline) }
                    .fixedSize()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Text("Speed snaps so every video loops seamlessly. Double-tap the preview to pause.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }
}
