import SwiftUI

/// A white card with an icon and title, something on the title's right
/// (a caption or the night stepper), and the chart below.
struct ChartCard<Trailing: View, Content: View>: View {
    let title: String
    let icon: String
    let trailing: Trailing
    let content: Content

    init(_ title: String, icon: String, @ViewBuilder trailing: () -> Trailing, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.blue)
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                Spacer()
                trailing
            }
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .card()
    }
}

/// A card's one-line summary, beside its title.
struct Caption: View {
    let text: String?

    init(_ text: String?) { self.text = text }

    var body: some View {
        if let text { Text(text).font(.system(size: 12)).foregroundStyle(Theme.sub) }
    }
}

/// ‹ Sat, May 31 › — steps the Sleep Breakdown through the window's nights.
struct NightStepper: View {
    let night: Hypnogram
    @Environment(DashboardModel.self) private var model

    var body: some View {
        HStack(spacing: 4) {
            Button { model.stepNight(older: true) } label: { Image(systemName: "chevron.left") }
                .disabled(!model.canStepNight(older: true))
                .help("Previous night")
            Text(Theme.day(night.night)?.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) ?? night.night)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.ink)
                .frame(minWidth: 84)
            Button { model.stepNight(older: false) } label: { Image(systemName: "chevron.right") }
                .disabled(!model.canStepNight(older: false))
                .help("Next night")
        }
        .buttonStyle(.borderless)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Theme.sub)
    }
}
