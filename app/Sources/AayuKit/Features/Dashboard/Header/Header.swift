import SwiftUI

/// Greeting and subtitle, the month control and Settings button, and the
/// Sleep Score panel, on the dark header. The background runs edge to edge;
/// the content lines up with the page's tiles (same inset, same width cap).
struct Header: View {
    let d: Dashboard
    @Environment(\.colorScheme) private var colorScheme   // the window's, outside the override below

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(Greeting.now), \(Greeting.firstName)")
                        .font(Theme.largeTitle)
                        .foregroundStyle(.white)
                        .accessibilityAddTraits(.isHeader)
                    Text("Here’s your health overview for \(Theme.rangePhrase(d.selection)).")
                        .font(Theme.body)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                Spacer(minLength: 16)
                MonthControl(d: d)
                SettingsLink {
                    Image(systemName: "gearshape")
                        .font(Theme.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(FrostedButtonStyle(shape: Circle()))
                .help("Settings (⌘,)")
                .accessibilityLabel("Settings")
            }
            ScorePanel(d: d)
        }
        .padding(.horizontal, Theme.inset)
        .padding(.top, 40)       // below the traffic lights
        .padding(.bottom, 24)
        .frame(maxWidth: Theme.maxContentWidth)
        .frame(maxWidth: .infinity)
        .background(HeaderBackground())
        .overlay(alignment: .bottom) {
            // In Dark the page is navy too; a faint line keeps the header's edge.
            if colorScheme == .dark { Rectangle().fill(Theme.headerRule).frame(height: 1) }
        }
        .environment(\.colorScheme, .dark)   // the header is dark in both appearances
        .measuringLayoutClass()
    }
}

/// The dark gradient with a violet glow; dragging it moves the window (there's no title bar).
struct HeaderBackground: View {
    var body: some View {
        Rectangle()
            .fill(Theme.header)
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(RadialGradient(colors: [Theme.violet.opacity(0.35), .clear], center: .center,
                                         startRadius: 0, endRadius: 360))
                    .frame(width: 720, height: 720)
                    .offset(x: 200, y: -320)
            }
            .clipped()
            .gesture(WindowDragGesture())
            .allowsWindowActivationEvents(true)
            .accessibilityHidden(true)
    }
}

/// "Good morning, Sai".
enum Greeting {
    static var now: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: String(localized: "Good morning")
        case 12..<17: String(localized: "Good afternoon")
        default: String(localized: "Good evening")
        }
    }

    /// The Mac account's first name ("Sai" from "Sai Nikhil Kunapareddy").
    static let firstName = NSFullUserName().split(separator: " ").first.map(String.init) ?? NSUserName()
}
