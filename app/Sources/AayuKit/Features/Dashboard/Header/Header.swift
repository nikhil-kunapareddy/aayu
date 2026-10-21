import SwiftUI

/// Greeting and subtitle, the month control and Settings button, and the
/// Sleep Score panel, on the dark header.
struct Header: View {
    let d: Dashboard

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(Greeting.now), \(Greeting.firstName)")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Here’s your health overview for \(Theme.rangePhrase(d.selection)).")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                MonthControl(d: d)
                SettingsLink {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .frosted(Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Settings (⌘,)")
            }
            ScorePanel(d: d)
        }
        .padding(.horizontal, Theme.inset + 4)
        .padding(.top, 40)       // below the traffic lights
        .padding(.bottom, 22)
        .background(HeaderBackground())
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
    }
}

/// "Good morning, Sai".
enum Greeting {
    static var now: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    /// The Mac account's first name ("Sai" from "Sai Nikhil Kunapareddy").
    static let firstName = NSFullUserName().split(separator: " ").first.map(String.init) ?? NSUserName()
}
