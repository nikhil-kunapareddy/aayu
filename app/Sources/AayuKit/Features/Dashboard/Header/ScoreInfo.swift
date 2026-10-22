import SwiftUI

/// The ⓘ beside "Sleep Score": a popover saying, in plain words, what the score
/// is made of. Its points and targets mirror the backend's sleep score
/// (`series.py`: the weights, 7.5 hours, 2 awakenings); change them together.
struct ScoreInfoButton: View {
    let parts: ScoreParts?
    @AppStorage(Pref.bedtime) private var bedtime = ClockTime.bedtime
    @AppStorage(Pref.wakeTime) private var wakeTime = ClockTime.wakeTime
    @State private var showing = false

    var body: some View {
        Button { showing.toggle() } label: {
            Image(systemName: "info")
                .font(Theme.micro.weight(.bold))
                .foregroundStyle(Theme.headerInk)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(FrostedButtonStyle(shape: Circle()))
        .help("How the sleep score works")
        .accessibilityLabel("How the sleep score works")
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            // A score without an awakenings part came from nights with no stage minutes.
            ScoreInfo(bedtime: bedtime, wakeTime: wakeTime, noAwakenings: parts != nil && parts?.awakenings == nil)
        }
    }
}

/// What the popover says: the 14 nights, then each part with its points.
struct ScoreInfo: View {
    let bedtime: ClockTime
    let wakeTime: ClockTime
    var noAwakenings = false

    var body: some View {
        let bed = Theme.clockTime(bedtime), wake = Theme.clockTime(wakeTime)
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("How the score works")
                    .font(Theme.title3)
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("Your last 14 nights, out of 100 points.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.sub)
            }
            Grid(alignment: .topLeading, horizontalSpacing: 14, verticalSpacing: 10) {
                row(30, "Timing", "Going to bed and getting up near your targets, \(bed) and \(wake).")
                row(25, "Sleep stages", "A mix close to 20% deep, 22% REM and 53% light sleep, with little time awake.")
                row(20, "Time asleep", "About 7.5 hours a night.")
                row(15, "Steady schedule", "Going to bed and getting up at about the same time each night.")
                row(10, "Awakenings", "Waking up 2 times a night or fewer.")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Each part gives full points near its target, and fewer the further off you are.")
                if noAwakenings {
                    Text("Your watch didn’t record sleep stages for these nights, so awakenings are left out and the other parts count for more.")
                }
                Text("You can change the target times in Settings (⌘,).")
            }
            .font(Theme.caption)
            .foregroundStyle(Theme.sub)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 340, alignment: .leading)
    }

    private func row(_ points: Int, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        GridRow {
            Text(points.formatted())
                .font(Theme.title3.monospacedDigit())
                .foregroundStyle(Theme.ink)
                .gridColumnAlignment(.trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.bodyEmphasis).foregroundStyle(Theme.ink)
                Text(detail).font(Theme.caption).foregroundStyle(Theme.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)   // the rest of the popover's width
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(String(localized: "^[\(points) point](inflect: true)"))
    }
}
