import SwiftUI

extension View {
    /// A white (in Dark, navy) card on the page.
    func card(padding inset: CGFloat = 20) -> some View {
        padding(inset)
            .background(Theme.card, in: .rect(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.border))
            .shadow(color: Theme.night.opacity(0.04), radius: 8, y: 2)
    }

    /// A frosted shape on the dark header.
    func frosted<S: InsettableShape>(_ shape: S) -> some View {
        background(Theme.panel, in: shape).overlay(shape.strokeBorder(Theme.panelStroke))
    }
}
