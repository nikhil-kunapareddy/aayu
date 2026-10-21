import SwiftUI

/// A KPI: a colored icon badge and title, the value with its unit, and its
/// change. VoiceOver reads it as one element: "Resting Heart Rate, 58 beats
/// per minute, down 2 bpm vs April, better".
struct StatTile: View {
    let title: String
    let badge: (icon: String, color: Color)
    let value: String?
    let number: Double?        // the value as a number, for the counting transition
    let unit: String?
    let spokenValue: String?   // the value with its unit in words ("58 beats per minute")
    let change: ChangeLabel?
    let help: String
    @Environment(\.layoutClass) private var layout
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: badge.icon)
                    .font(Theme.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(badge.color.gradient, in: Circle())
                Text(title)
                    .font(Theme.bodyEmphasis)
                    .foregroundStyle(Theme.sub)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value ?? "—")
                        .font(layout == .compact ? Theme.metricCompact : Theme.metric)
                        .foregroundStyle(Theme.ink)
                        .contentTransition(.numericText(value: number ?? 0))
                        .animation(reduceMotion ? nil : .smooth, value: number)
                    if let unit, value != nil {
                        Text(unit).font(Theme.title3.weight(.medium)).foregroundStyle(Theme.sub)
                    }
                }
                .lineLimit(1)
                if let change {
                    change
                } else {
                    Text("No earlier data to compare").font(Theme.caption).foregroundStyle(Theme.sub)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card(padding: 20)
        .help(help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        guard value != nil, let spoken = spokenValue else { return String(localized: "No data") }
        guard let change else { return spoken }
        return String(localized: "\(spoken), \(change.accessibilityText)")
    }
}
