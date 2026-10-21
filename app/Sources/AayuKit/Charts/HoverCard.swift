import SwiftUI

/// The tooltip shown above the hovered day: a title and colored value rows.
struct HoverCard: View {
    let title: String
    let rows: [(String, String, Color)]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).fontWeight(.semibold).foregroundStyle(Theme.ink)
            ForEach(rows.indices, id: \.self) { i in
                HStack(spacing: 6) {
                    Circle().fill(rows[i].2).frame(width: 7, height: 7)
                    Text(rows[i].0).foregroundStyle(Theme.sub)
                    Spacer(minLength: 12)
                    Text(rows[i].1).foregroundStyle(Theme.ink).monospacedDigit()
                }
            }
        }
        .font(Theme.micro)
        .padding(12)
        .frame(minWidth: 150)
        .background(Theme.card, in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
        .shadow(color: Theme.night.opacity(0.12), radius: 12, y: 4)
    }
}
