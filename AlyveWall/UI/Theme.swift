import SwiftUI

enum Theme {
    static let background = Color(red: 0.03, green: 0.03, blue: 0.045)
    static let card = Color.white.opacity(0.06)
    static let stroke = Color.white.opacity(0.1)
    static let accent = Color(red: 0.93, green: 0.36, blue: 0.62)
    static let glow = LinearGradient(colors: [Color(red: 0.55, green: 0.36, blue: 0.96), Color(red: 0.93, green: 0.29, blue: 0.6),
                                              Color(red: 0.98, green: 0.62, blue: 0.24)],
                                     startPoint: .leading, endPoint: .trailing)
    static let gold = LinearGradient(colors: [Color(red: 1, green: 0.84, blue: 0.4), Color(red: 0.95, green: 0.6, blue: 0.2)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing)
}

struct Wordmark: View {
    var size: CGFloat = 18
    var body: some View {
        HStack(spacing: size * 0.35) {
            Text("ALYVE").foregroundStyle(Theme.glow)
            Text("WALL").foregroundStyle(.white)
        }
        .font(.system(size: size, weight: .heavy, design: .rounded))
        .tracking(size * 0.22)
    }
}

/// A labelled slider row used across the panels.
struct SliderRow: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var display: (Double) -> String = { "\(Int(($0 * 100).rounded()))%" }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                Text(display(value)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
        }
    }
}

struct PremiumBadge: View {
    var body: some View {
        Image(systemName: "crown.fill")
            .font(.caption2.weight(.bold))
            .foregroundStyle(Theme.gold)
    }
}
