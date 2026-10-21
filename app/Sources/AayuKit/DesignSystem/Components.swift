import SwiftUI

/// A small colored dot, for legends.
struct Swatch: View {
    let color: Color
    var size: CGFloat = 8

    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
    }
}

/// "↗ +12% vs April" — a change, green when it's an improvement.
///
/// The sentence comes from the caller (`phrase`), which gets the number to put
/// in it: "+12" for the label, "12" for VoiceOver, which says "up 12% vs April,
/// better". Callers build it with `String(localized:)`, so a translation can
/// move the number.
struct ChangeLabel: View {
    /// Whether a change reads as better, worse, or neither.
    enum Tone { case better, worse, neutral }
    /// The page (white cards) or the dark header.
    enum Surface { case page, header }

    let text: String           // "−3 bpm vs April"
    let spoken: String         // "down 3 bpm vs April"
    let change: Double         // as shown, rounded; its sign gives the arrow
    let higherIsBetter: Bool?  // nil: no judgment (shown gray)
    var surface = Surface.page

    /// `change` is rounded to `decimals` places for the text, the arrow and the
    /// colour alike, so a change shown as "±0.0" reads as none.
    init(_ change: Double, decimals: Int = 0, higherIsBetter: Bool?, surface: Surface = .page,
         locale: Locale = .autoupdatingCurrent, phrase: (String) -> String) {
        let shown = Theme.rounded(change, decimals: decimals)
        let magnitude = phrase(abs(shown).formatted(.number.precision(.fractionLength(decimals)).locale(locale)))
        self.text = phrase(Theme.signed(change, decimals: decimals, locale: locale))
        self.spoken = shown > 0 ? String(localized: "up \(magnitude)")
            : shown < 0 ? String(localized: "down \(magnitude)") : String(localized: "unchanged, \(magnitude)")
        self.change = shown
        self.higherIsBetter = higherIsBetter
        self.surface = surface
    }

    /// "+12" + `suffix`.
    init(_ change: Double, decimals: Int = 0, suffix: String, higherIsBetter: Bool?) {
        self.init(change, decimals: decimals, higherIsBetter: higherIsBetter) { $0 + suffix }
    }

    var body: some View {
        Label(text, systemImage: change > 0 ? "arrow.up.right" : change < 0 ? "arrow.down.right" : "arrow.right")
            .font(Theme.caption.weight(.semibold))
            .foregroundStyle(color)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
    }

    var tone: Tone {
        guard let higherIsBetter, change != 0 else { return .neutral }
        return (change > 0) == higherIsBetter ? .better : .worse
    }

    /// What VoiceOver reads: "down 2 bpm vs April, better".
    var accessibilityText: String {
        switch tone {
        case .better: String(localized: "\(spoken), better")
        case .worse: String(localized: "\(spoken), worse")
        case .neutral: spoken
        }
    }

    /// The text colour for this tone, on this surface.
    var color: Color {
        switch (tone, surface) {
        case (.better, .page): Theme.up
        case (.worse, .page): Theme.down
        case (.neutral, .page): Theme.sub
        case (.better, .header): Theme.upOnDark
        case (.worse, .header): Theme.downOnDark
        case (.neutral, .header): .white.opacity(0.75)
        }
    }
}

/// A chart's key, for a card's header: a short line (for lines) or a dot (for bars) per series.
struct ChartLegend: View {
    struct Item {
        let name: String
        let color: Color
        var line: CGFloat? = nil   // a line's weight; nil draws a dot
    }

    let items: [Item]

    var body: some View {
        HStack(spacing: 16) {
            ForEach(items, id: \.name) { item in
                HStack(spacing: 6) {
                    if let line = item.line {
                        Capsule().fill(item.color).frame(width: 14, height: max(line, 2))
                    } else {
                        RoundedRectangle(cornerRadius: 2).fill(item.color).frame(width: 8, height: 8)
                    }
                    Text(item.name).font(Theme.caption).foregroundStyle(Theme.sub)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// A chart card with nothing to draw.
struct EmptyChart: View {
    let title: String
    let icon: String
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(message)
        }
        .foregroundStyle(Theme.sub)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
