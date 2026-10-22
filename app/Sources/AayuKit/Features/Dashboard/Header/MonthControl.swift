import SwiftUI

/// ‹ | 📅 May 2026 ⌄ | › in one frosted capsule. Each part highlights on its
/// own; the label opens a native menu of the ranges, grouped by year.
struct MonthControl: View {
    let d: Dashboard
    @Environment(DashboardModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            Button { model.step(older: true) } label: {
                Image(systemName: "chevron.left").frame(width: 40, height: 40)
            }
            .buttonStyle(FrostedButtonStyle(shape: UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20),
                                            standalone: false))
            .disabled(!model.canStep(older: true))
            .help("Previous month (⌘←)")
            .accessibilityLabel("Previous month")
            separator
            RangeMenu(d: d)
            separator
            Button { model.step(older: false) } label: {
                Image(systemName: "chevron.right").frame(width: 40, height: 40)
            }
            .buttonStyle(FrostedButtonStyle(shape: UnevenRoundedRectangle(bottomTrailingRadius: 20, topTrailingRadius: 20),
                                            standalone: false))
            .disabled(!model.canStep(older: false))
            .help("Next month (⌘→)")
            .accessibilityLabel("Next month")
        }
        .font(Theme.body.weight(.semibold))
        .foregroundStyle(Theme.headerInk)
        .frosted(Capsule())
        .accessibilityElement(children: .contain)
    }

    private var separator: some View {
        Rectangle().fill(Theme.panelStroke).frame(width: 1, height: 24).accessibilityHidden(true)
    }
}

/// The range label; opens a menu of "Last 30 days" and the months, a section per year.
struct RangeMenu: View {
    let d: Dashboard
    @Environment(DashboardModel.self) private var model

    var body: some View {
        Menu {
            Picker("Period", selection: Binding(get: { d.selection }, set: { model.select($0) })) {
                ForEach(Self.sections(d.options), id: \.title) { section in
                    if section.title.isEmpty {
                        ForEach(section.options, id: \.self) { Text(Theme.rangeLabel($0)).tag($0) }
                    } else {
                        Section(section.title) {
                            ForEach(section.options, id: \.self) { Text(Self.monthName($0)).tag($0) }
                        }
                    }
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                Text(Theme.rangeLabel(d.selection)).font(Theme.body.weight(.medium))
                Image(systemName: "chevron.down").font(Theme.micro.weight(.bold)).opacity(0.7)
            }
            .padding(.horizontal, 16)
            .frame(height: 40)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(FrostedButtonStyle(shape: Rectangle(), standalone: false))
        .fixedSize()
        .help("Choose a month")
        .accessibilityLabel("Period")
        .accessibilityValue(Theme.rangeLabel(d.selection))
    }

    /// "Last 30 days" on its own, then the months by year, newest first
    /// (the backend's order). A section's title is its year ("" for the loose options).
    static func sections(_ options: [String]) -> [(title: String, options: [String])] {
        var sections: [(title: String, options: [String])] = []
        for option in options {
            let year = Theme.month(option) == nil ? "" : String(option.prefix(4))
            if let last = sections.last, last.title == year {
                sections[sections.count - 1].options.append(option)
            } else {
                sections.append((year, [option]))
            }
        }
        return sections
    }

    /// '2026-05' → "May".
    static func monthName(_ option: String, locale: Locale = .autoupdatingCurrent,
                          timeZone: TimeZone = .autoupdatingCurrent) -> String {
        guard let date = Theme.month(option, timeZone: timeZone) else { return option }
        var calendar = Theme.gregorian(timeZone)
        calendar.locale = locale
        return date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone).month(.wide))
    }
}
