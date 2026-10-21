import SwiftUI

/// A white card: an icon, the title and its caption on the left, an accessory
/// on the right (the chart's legend, or the night stepper), and the chart below.
/// The header row has a fixed height, so every chart starts at the same place.
struct ChartCard<Accessory: View, Content: View>: View {
    let title: String
    let icon: String
    let caption: String?
    let accessory: Accessory
    let content: Content

    init(_ title: String, icon: String, caption: String? = nil, @ViewBuilder accessory: () -> Accessory,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.caption = caption
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(Theme.title3)
                    .foregroundStyle(Theme.blue)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title).font(Theme.title3).foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                    if let caption {
                        Text(caption).font(Theme.caption).foregroundStyle(Theme.sub)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 16)
                accessory
            }
            .frame(height: 24)
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .card()
    }
}

/// ‹ Sat, May 31 › — steps the Sleep Breakdown through the window's nights.
struct NightStepper: View {
    let night: Hypnogram
    @Environment(DashboardModel.self) private var model

    var body: some View {
        HStack(spacing: 4) {
            step(older: true)
            Text(Theme.day(night.night)?.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) ?? night.night)
                .font(Theme.caption.weight(.medium))
                .foregroundStyle(Theme.ink)
                .frame(minWidth: 84)
            step(older: false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Night")
    }

    private func step(older: Bool) -> some View {
        Button { model.stepNight(older: older) } label: {
            Image(systemName: older ? "chevron.left" : "chevron.right")
                .font(Theme.micro.weight(.bold))
                .foregroundStyle(Theme.sub)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(CardButtonStyle(shape: Circle()))
        .disabled(!model.canStepNight(older: older))
        .help(older ? "Previous night" : "Next night")
        .accessibilityLabel(older ? "Previous night" : "Next night")
    }
}
