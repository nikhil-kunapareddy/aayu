import SwiftUI

/// A small colored dot, for legends.
struct Swatch: View {
    let color: Color
    var size: CGFloat = 9

    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
    }
}

/// "↗ +12% vs April" — a change, green when it's an improvement.
struct ChangeLabel: View {
    /// Whether a change reads as better, worse, or neither.
    enum Tone { case better, worse, neutral }

    let text: String
    let change: Double         // as shown, rounded; its sign gives the arrow
    let higherIsBetter: Bool?  // nil: no judgment (shown gray)

    /// "+12" + `suffix`. `change` is rounded to `decimals` places for the text,
    /// the arrow and the colour alike, so a change shown as "±0.0" reads as none.
    init(_ change: Double, decimals: Int = 0, suffix: String, higherIsBetter: Bool?) {
        self.text = Theme.signed(change, decimals: decimals) + suffix
        self.change = Theme.rounded(change, decimals: decimals)
        self.higherIsBetter = higherIsBetter
    }

    var body: some View {
        Label(text, systemImage: change > 0 ? "arrow.up.right" : change < 0 ? "arrow.down.right" : "arrow.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
    }

    var tone: Tone {
        guard let higherIsBetter, change != 0 else { return .neutral }
        return (change > 0) == higherIsBetter ? .better : .worse
    }

    private var color: Color {
        switch tone {
        case .better: Theme.up
        case .worse: Theme.down
        case .neutral: Theme.sub
        }
    }
}

/// The Aayu mark — drawn from the app icon itself, so the two never drift apart.
struct AayuLogo: View {
    var size: CGFloat = 40

    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}
