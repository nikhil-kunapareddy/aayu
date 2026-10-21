import SwiftUI

// Button styles with hover, pressed, disabled and keyboard-focus states. The
// focus ring (Full Keyboard Access) follows the button's shape. No pointing-hand
// cursors: Mac controls keep the arrow.

/// A frosted control on the dark header: white 5% at rest, 12% on hover, 18%
/// pressed; a disabled label dims to 35%.
///
/// `standalone: false` is for a segment inside an already-frosted container
/// (the month control): it adds only the difference over the container's 5%.
struct FrostedButtonStyle<S: Shape>: ButtonStyle {
    var shape: S
    var standalone = true

    func makeBody(configuration: Configuration) -> some View {
        FrostedButton(configuration: configuration, shape: shape, standalone: standalone)
    }
}

extension FrostedButtonStyle where S == Capsule {
    init() { self.init(shape: Capsule()) }
}

private struct FrostedButton<S: Shape>: View {
    let configuration: ButtonStyleConfiguration
    let shape: S
    let standalone: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        configuration.label
            .opacity(isEnabled ? 1 : 0.35)
            .background(Color.white.opacity(fill), in: shape)
            .overlay {
                // A 1-pt border just inside the shape, as `strokeBorder` draws it.
                if standalone { shape.stroke(Theme.panelStroke, lineWidth: 1).padding(0.5) }
            }
            .contentShape(shape)
            .contentShape(.focusEffect, shape)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }

    /// The white fill's opacity; a segment's composites with its container's 5%.
    private var fill: Double {
        let (rest, hover, pressed) = standalone ? (0.05, 0.12, 0.18) : (0, 0.074, 0.137)
        guard isEnabled else { return rest }
        return configuration.isPressed ? pressed : hovering ? hover : rest
    }
}

/// A small control on a card or the page: the page color shows through on
/// hover and it shrinks a touch while pressed. `resting` fills it otherwise
/// (`Theme.card` for the pager's floating arrows; clear for inline steppers).
struct CardButtonStyle<S: Shape>: ButtonStyle {
    var shape: S
    var resting: Color = .clear

    func makeBody(configuration: Configuration) -> some View {
        CardButton(configuration: configuration, shape: shape, resting: resting)
    }
}

private struct CardButton<S: Shape>: View {
    let configuration: ButtonStyleConfiguration
    let shape: S
    let resting: Color
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        configuration.label
            .opacity(isEnabled ? 1 : 0.35)
            .background(hovering && isEnabled ? Theme.page : resting, in: shape)
            .scaleEffect(configuration.isPressed && isEnabled ? 0.95 : 1)
            .contentShape(shape)
            .contentShape(.focusEffect, shape)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

/// A pager dot: it grows a little under the pointer and dips when pressed.
struct DotButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        DotButton(configuration: configuration)
    }
}

private struct DotButton: View {
    let configuration: ButtonStyleConfiguration
    @State private var hovering = false

    var body: some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : hovering ? 1.2 : 1)
            .contentShape(Capsule())
            .contentShape(.focusEffect, Capsule())
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
