import SwiftUI

/// "Bio Age", beside the Sleep Score: the bio age with its gap to your age, and
/// the pace of aging on a −1× … 3× gauge. The ⓘ lists what each marker adds
/// (`BioAgeInfo`). Without a birth date it asks for one; without enough data it says so.
/// The numbers come from backend/aayu_backend/bioage.py.
struct BioAgePanel: View {
    let d: Dashboard
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Bio Age")
                    .font(Theme.title2)
                    .foregroundStyle(Theme.headerInk)
                    .accessibilityAddTraits(.isHeader)
                if let bio = d.bioAge { BioAgeInfoButton(bio: bio) }
            }
            content
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frosted(RoundedRectangle(cornerRadius: Theme.panelRadius))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var content: some View {
        if let bio = d.bioAge, let value = bio.bioAge {
            HStack(alignment: .center, spacing: 14) {
                Text(value, format: .number.precision(.fractionLength(1)))
                    .font(Theme.score)
                    .foregroundStyle(Theme.headerInk)
                    .contentTransition(.numericText(value: value))
                    .animation(reduceMotion ? nil : .smooth, value: value)
                VStack(alignment: .leading, spacing: 6) {
                    ScorePill(change: ChangeLabel(value - bio.age, decimals: 1, higherIsBetter: false,
                                                  surface: .header) {
                        String(localized: "\($0) years")
                    })
                    Text("vs your age, \(bio.age, format: .number.precision(.fractionLength(1)))")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.headerInk.opacity(0.75))
                }
            }
            .accessibilityElement(children: .combine)
            .help(String(localized: """
                Your age, plus or minus the years your steps, sleep, sleep regularity, BMI and resting heart \
                rate add, over the 90 days up to \(bio.end.formatted(.dateTime.month(.wide).day())).
                """))
            PaceView(pace: bio.pace)
        } else if d.bioAge != nil {
            message(String(localized: """
                Not enough data yet. Bio age needs at least three of steps, time asleep, sleep regularity, \
                BMI and resting heart rate over 90 days.
                """))
        } else {
            message(String(localized: "Add your date of birth to see your bio age and pace of aging."))
            SettingsLink {
                Text("Open Settings…")
                    .font(Theme.bodyEmphasis)
                    .foregroundStyle(Theme.headerInk)
                    .padding(.horizontal, 14)
                    .frame(height: 30)
            }
            .buttonStyle(FrostedButtonStyle(shape: Capsule()))
            .help("Settings (⌘,)")
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(Theme.body)
            .foregroundStyle(Theme.headerInk.opacity(0.75))
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// "Pace of aging 1.2×", a gauge from −1× to 3× with a mark at 1× (the calendar), and what it means.
struct PaceView: View {
    let pace: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Pace of aging")
                    .font(Theme.bodyEmphasis)
                    .foregroundStyle(Theme.headerInk.opacity(0.85))
                Spacer(minLength: 8)
                Text(pace.map { Theme.pace($0) } ?? "—")
                    .font(Theme.title2.monospacedDigit())
                    .foregroundStyle(Theme.headerInk)
            }
            PaceGauge(pace: pace)
                .frame(height: 12)
            Text(caption)
                .font(Theme.caption)
                .foregroundStyle(Theme.headerInk.opacity(0.75))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pace of aging")
        .accessibilityValue(pace.map { String(localized: "\(Theme.pace($0)), \(caption)") } ?? caption)
        .help(String(localized: """
            Years of bio age gained per calendar year, from how your markers moved over up to the last 6 months. \
            1× keeps pace with the calendar.
            """))
    }

    private var caption: String {
        guard let pace else { return String(localized: "Needs about 3 months of data.") }
        return pace < 0.95 ? String(localized: "Slower than the calendar")
            : pace > 1.05 ? String(localized: "Faster than the calendar")
            : String(localized: "In step with the calendar")
    }
}

/// A track from −1× to 3×: a tick at 1×, a bar from it to the pace (green when
/// slower, orange when faster) and a dot on the pace.
struct PaceGauge: View {
    let pace: Double?

    nonisolated static let range = -1.0...3.0

    /// Where `value` sits along `width`, clamped to the range.
    nonisolated static func x(_ value: Double, width: CGFloat) -> CGFloat {
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        return CGFloat((clamped - range.lowerBound) / (range.upperBound - range.lowerBound)) * width
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, mid = geo.size.height / 2
            let one = Self.x(1, width: w)
            ZStack(alignment: .topLeading) {
                Capsule().fill(Theme.headerInk.opacity(0.10)).frame(height: 6).offset(y: mid - 3)
                if let pace {
                    let at = Self.x(pace, width: w)
                    Capsule()
                        .fill(pace <= 1 ? Theme.headerUp : Theme.headerDown)
                        .frame(width: max(abs(at - one), 6), height: 6)
                        .offset(x: min(at, one) - (abs(at - one) < 6 ? 3 : 0), y: mid - 3)
                }
                Rectangle().fill(Theme.headerInk.opacity(0.55)).frame(width: 2, height: 12).offset(x: one - 1)
                if let pace {
                    Circle()
                        .fill(Theme.headerInk)
                        .frame(width: 10, height: 10)
                        .offset(x: Self.x(pace, width: w) - 5, y: mid - 5)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// The ⓘ beside "Bio Age": a popover with each marker's value and years, and how it's worked out.
struct BioAgeInfoButton: View {
    let bio: BioAge
    @State private var showing = false

    var body: some View {
        Button { showing.toggle() } label: {
            Image(systemName: "info")
                .font(Theme.micro.weight(.bold))
                .foregroundStyle(Theme.headerInk)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(FrostedButtonStyle(shape: Circle()))
        .help("What’s behind your bio age")
        .accessibilityLabel("What’s behind your bio age")
        .popover(isPresented: $showing, arrowEdge: .bottom) { BioAgeInfo(bio: bio) }
    }
}

/// What the popover says: the markers, then the method and its limits. The
/// reference values and the 3-year cap mirror bioage.py; change them together.
struct BioAgeInfo: View {
    let bio: BioAge

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("What’s behind your bio age")
                    .font(Theme.title3)
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("The 90 days up to \(bio.end.formatted(.dateTime.month(.wide).day())). Each marker adds or takes off years.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                ForEach(bio.markers) { row($0) }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("""
                    Each marker’s years come from how strongly it’s linked with mortality in large studies, \
                    set against how that risk rises with age (it doubles about every 8 years). A marker counts \
                    zero at its reference and adds at most 3 years either way.
                    """)
                Text("Pace of aging is how fast your bio age moved over up to the last 6 months: 1× keeps pace with the calendar.")
                Text("""
                    An estimate from observational studies, not a medical test. The markers overlap, so adding \
                    them up overstates a little, and your export has no HRV or VO₂ max to include.
                    """)
                Text(birthLine)
                Text("""
                    Sources: Banach 2023 (steps), Windred 2024 (sleep regularity), Global BMI Mortality \
                    Collaboration 2016, Yin 2017 (time asleep), Zhang 2016 (resting heart rate).
                    """)
            }
            .font(Theme.caption)
            .foregroundStyle(Theme.sub)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 420, alignment: .leading)
    }

    private var birthLine: String {
        bio.birthSource == "zepp"
            ? String(localized: """
                Your Zepp profile has only your birth month, so your age counts from the 15th. \
                Set your date of birth in Settings (⌘,).
                """)
            : String(localized: "Your age counts from the date of birth in Settings (⌘,).")
    }

    private func row(_ marker: BioMarker) -> some View {
        let text = BioMarkerText(marker)
        return GridRow {
            VStack(alignment: .leading, spacing: 2) {
                Text(text.title).font(Theme.bodyEmphasis).foregroundStyle(Theme.ink)
                Text(text.reference).font(Theme.caption).foregroundStyle(Theme.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(text.value)
                .font(Theme.body.monospacedDigit())
                .foregroundStyle(Theme.ink)
                .gridColumnAlignment(.trailing)
            YearsBar(years: marker.years)
                .frame(width: 72, height: 6)
            Text(text.years)
                .font(Theme.bodyEmphasis.monospacedDigit())
                .foregroundStyle(text.color)
                .gridColumnAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A marker's years as a bar out from the middle: left (green) for younger, right (orange) for older.
struct YearsBar: View {
    let years: Double?

    var body: some View {
        GeometryReader { geo in
            let half = geo.size.width / 2
            let share = CGFloat(min(abs(years ?? 0), 3) / 3)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.grid)
                if let years, years != 0 {
                    Capsule()
                        .fill(years < 0 ? Theme.up : Theme.down)
                        .frame(width: max(share * half, 3))
                        .offset(x: years < 0 ? half - max(share * half, 3) : half)
                }
                Rectangle().fill(Theme.sub).frame(width: 1).offset(x: half - 0.5)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A marker's name, reference, value and years, as the popover shows them.
struct BioMarkerText {
    let title: String
    let reference: String
    let value: String
    let years: String
    let color: Color

    init(_ marker: BioMarker, locale: Locale = .autoupdatingCurrent) {
        let v = marker.value
        func number(_ x: Double, _ digits: Int) -> String {
            x.formatted(.number.precision(.fractionLength(digits)).locale(locale))
        }
        switch marker.key {
        case "steps":
            title = String(localized: "Daily steps")
            reference = String(localized: "Zero at 7,000 a day")
            value = v.map { String(localized: "\(number($0, 0)) a day") } ?? "—"
        case "regularity":
            title = String(localized: "Sleep regularity")
            reference = String(localized: "Zero at 81, a typical score")
            value = v.map { String(localized: "SRI \(number($0, 0))") } ?? "—"
        case "bmi":
            title = String(localized: "BMI")
            reference = String(localized: "Zero from 18.5 to 25")
            value = v.map { number($0, 1) } ?? "—"
        case "sleep":
            title = String(localized: "Time asleep")
            reference = String(localized: "Zero from 7 to 8 hours")
            value = v.map { String(localized: "\(number($0, 1)) h") } ?? "—"
        case "resting_hr":
            title = String(localized: "Resting heart rate")
            reference = String(localized: "Zero at 60 bpm")
            value = v.map { String(localized: "\(number($0, 0)) bpm") } ?? "—"
        default:
            title = marker.key
            reference = ""
            value = v.map { number($0, 1) } ?? "—"
        }
        if let y = marker.years {
            years = String(localized: "\(Theme.signed(y, decimals: 1, locale: locale)) yrs")
            let shown = Theme.rounded(y, decimals: 1)
            color = shown > 0 ? Theme.down : shown < 0 ? Theme.up : Theme.sub
        } else {
            years = v == nil ? String(localized: "No data") : String(localized: "Not scored")
            color = Theme.sub
        }
    }
}
