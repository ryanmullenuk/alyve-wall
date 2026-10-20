import SwiftUI

struct PremiumView: View {
    @Environment(PremiumStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let perks: [(String, String, String)] = [
        ("drop.halffull", "No watermark", "Clean wallpapers on every export."),
        ("display", "Mac sizes up to 5K", "Full HD, QHD, MacBook Air and Pro, 4K and 5K."),
        ("iphone", "Native iPhone sizes", "Full HD plus pixel-perfect iPhone Pro and Pro Max."),
        ("livephoto", "Full HD Live Photos", "Sharp, watermark-free Lock Screen wallpapers."),
        ("speedometer", "60 fps video", "Extra-smooth motion for your desktop."),
    ]

    var body: some View {
        ZStack {
            BrandBackdrop(dim: 0.55)
            RadialGradient(colors: [Theme.accent.opacity(0.35), .clear], center: .top, startRadius: 10, endRadius: 420)
                .ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                    HStack {
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark").font(.headline).padding(10).background(Theme.card, in: Circle())
                        }
                        .accessibilityLabel("Close")
                    }
                    Image(systemName: "crown.fill").font(.system(size: 52)).foregroundStyle(Theme.gold)
                    VStack(spacing: 6) {
                        Wordmark(size: 24)
                        Text("PREMIUM").font(.subheadline.weight(.heavy)).tracking(6).foregroundStyle(Theme.gold)
                    }
                    Text("One payment, yours for good. No subscription.")
                        .font(.subheadline).foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(perks, id: \.1) { perk in
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: perk.0).font(.title3).foregroundStyle(Theme.glow).frame(width: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(perk.1).font(.subheadline.weight(.semibold))
                                    Text(perk.2).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    if store.isPremium {
                        Label("Premium is unlocked", systemImage: "checkmark.seal.fill")
                            .font(.headline).foregroundStyle(Theme.gold)
                    } else {
                        Button {
                            Task { await store.purchase() }
                        } label: {
                            Group {
                                if store.isWorking {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("Unlock for \(store.price)")
                                }
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Theme.glow, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .foregroundStyle(.white)
                        }
                        .disabled(store.isWorking)

                        Button("Restore purchase") { Task { await store.restore() } }
                            .font(.subheadline)
                            .disabled(store.isWorking)
                    }

                    if let message = store.message {
                        Text(message).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }

                    if PremiumStore.isTesterBuild && !UserDefaults.standard.bool(forKey: "hideTester") {
                        Toggle("Unlock Premium for testing", isOn: Binding(get: { store.testerUnlocked }, set: { store.setTesterPremium($0) }))
                            .font(.footnote)
                            .padding(12)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                    }

                    Link("Terms of Use", destination: PremiumStore.termsURL)
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(20)
            }
        }
        .preferredColorScheme(.dark)
        #if targetEnvironment(macCatalyst)
        .frame(minWidth: 560, idealWidth: 600, minHeight: 760, idealHeight: 820)
        #endif
        .onChange(of: store.isPremium) { _, unlocked in
            if unlocked { Task { try? await Task.sleep(for: .seconds(1)); dismiss() } }
        }
    }
}
