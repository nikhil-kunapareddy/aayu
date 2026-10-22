import SwiftUI

/// Greeting and subtitle, the month control and Settings button, and the
/// Sleep Score panel, at the top of the window's gradient. The drag area runs
/// edge to edge; the content lines up with the page's tiles (same inset, same width cap).
struct Header: View {
    let d: Dashboard
    @Environment(DashboardModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(Greeting.now), \(Greeting.firstName)")
                        .font(Theme.largeTitle)
                        .foregroundStyle(Theme.headerInk)
                        .accessibilityAddTraits(.isHeader)
                    Text("Here’s your health overview for \(Theme.rangePhrase(d.selection)).")
                        .font(Theme.body)
                        .foregroundStyle(Theme.headerInk.opacity(0.7))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                Spacer(minLength: 16)
                if model.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Loading")
                }
                MonthControl(d: d)
                SettingsLink {
                    Image(systemName: "gearshape")
                        .font(Theme.body.weight(.semibold))
                        .foregroundStyle(Theme.headerInk)
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
        .background(HeaderBackground(clear: true))   // the window's gradient shows through
        .measuringLayoutClass()
    }
}

/// The header's gradient with a violet glow: dark, or (`light`) its pale counterpart.
struct HeaderGradient: View {
    var light = false

    var body: some View {
        Rectangle()
            .fill(light ? Theme.headerLight : Theme.header)
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(RadialGradient(colors: [Theme.violet.opacity(light ? 0.18 : 0.35), .clear], center: .center,
                                         startRadius: 0, endRadius: 360))
                    .frame(width: 720, height: 720)
                    .offset(x: 200, y: -320)
            }
            .clipped()
            .accessibilityHidden(true)
    }
}

/// The dark gradient; dragging it moves the window (there's no title bar).
/// `clear` keeps only the dragging: the dashboard's header, over `WindowBackground`.
struct HeaderBackground: View {
    var clear = false

    var body: some View {
        Group {
            if clear { Color.clear.contentShape(.rect) } else { HeaderGradient() }
        }
        .gesture(WindowDragGesture())
        .allowsWindowActivationEvents(true)
        .accessibilityHidden(true)
    }
}

/// Behind the dashboard and Settings: one gradient for the whole window — the
/// header's, fading into the page — so there's no seam under the header.
struct WindowBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HeaderGradient(light: colorScheme != .dark)
            .overlay(LinearGradient(colors: [.clear, Theme.page], startPoint: .top, endPoint: .bottom))
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
