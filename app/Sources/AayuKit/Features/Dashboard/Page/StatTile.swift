import SwiftUI

/// A KPI: a colored icon badge and title, the value with its unit, and its change.
struct StatTile: View {
    let title: String
    let badge: (icon: String, color: Color)
    let value: String?
    let unit: String?
    let change: ChangeLabel?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: badge.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(badge.color.gradient, in: Circle())
                Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.sub)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value ?? "—").font(.system(size: 30, weight: .semibold)).foregroundStyle(Theme.ink)
                if let unit, value != nil {
                    Text(unit).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.sub)
                }
            }
            .monospacedDigit()
            if let change {
                change
            } else {
                Text("No earlier data to compare").font(.system(size: 12)).foregroundStyle(Theme.sub)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 18)
    }
}
