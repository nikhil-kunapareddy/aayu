import SwiftUI

/// ‹ | 📅 May 2026 ⌄ | › in one frosted capsule.
struct MonthControl: View {
    let d: Dashboard
    @Environment(DashboardModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            Button { model.step(older: true) } label: {
                Image(systemName: "chevron.left").frame(width: 42, height: 40).contentShape(Rectangle())
            }
            .disabled(!model.canStep(older: true))
            .help("Previous month (⌘←)")
            separator
            RangePicker(d: d)
            separator
            Button { model.step(older: false) } label: {
                Image(systemName: "chevron.right").frame(width: 42, height: 40).contentShape(Rectangle())
            }
            .disabled(!model.canStep(older: false))
            .help("Next month (⌘→)")
        }
        .buttonStyle(.plain)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(.white)
        .frosted(Capsule())
    }

    private var separator: some View {
        Rectangle().fill(Theme.panelStroke).frame(width: 1, height: 22)
    }
}

/// The month label; opens a popover listing the months (and "Last 30 days").
struct RangePicker: View {
    let d: Dashboard
    @Environment(DashboardModel.self) private var model
    @State private var isOpen = false

    var body: some View {
        Button { isOpen.toggle() } label: {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                Text(Theme.rangeLabel(d.selection)).font(.system(size: 14, weight: .medium))
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).opacity(0.7)
            }
            .padding(.horizontal, 16)
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(d.options, id: \.self) { option in
                        RangeRow(label: Theme.rangeLabel(option), selected: option == d.selection) {
                            model.select(option)
                            isOpen = false
                        }
                    }
                }
                .padding(6)
            }
            .frame(width: 210)
            .frame(maxHeight: 360)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// One option in the range popover, highlighted on hover, ticked when selected.
struct RangeRow: View {
    let label: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(label).foregroundStyle(Theme.ink)
                Spacer()
                if selected { Image(systemName: "checkmark").foregroundStyle(Theme.blue) }
            }
            .font(.system(size: 13, weight: selected ? .semibold : .regular))
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(hovering ? Theme.page : .clear, in: .rect(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
