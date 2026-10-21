import SwiftUI
import UniformTypeIdentifiers

/// The main window: a dark header (greeting, month control, Sleep Score panel)
/// over a pale page of KPI tiles and chart cards.
struct DashboardView: View {
    @Environment(DashboardModel.self) private var model
    @AppStorage(Pref.folder) private var folder = ""
    @AppStorage(Pref.units) private var units = "lbs"
    @AppStorage(Pref.autoReload) private var autoReload = true

    var body: some View {
        content
            .frame(minWidth: 1180, minHeight: 860)
            .ignoresSafeArea()   // the header runs up under the traffic lights
            .task { await model.start() }
            .onChange(of: folder) { Task { await model.open() } }
            .onChange(of: units) { Task { await model.refresh() } }
            .onChange(of: autoReload) { _, enabled in Task { await model.setAutoReload(enabled) } }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .welcome:
            FolderPrompt(title: "Welcome to Aayu",
                         message: "Choose the folder you exported from the Zepp app: the one that "
                             + "contains SLEEP, ACTIVITY, BODY and the other data folders.")
        case .loading:
            ZStack {
                HeaderBackground()
                ProgressView().controlSize(.large).tint(.white)
            }
        case .failed(let message):
            FolderPrompt(title: "Can't Show Your Data", message: message)
        case .ready(let dashboard):
            VStack(spacing: 0) {
                Header(d: dashboard)
                Page(d: dashboard)
            }
            .background(Theme.page)
        }
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

// ── Header ────────────────────────────────────────────────────────────────────

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

/// Score ring and its story on the left, the window's stage mix on the right.
struct ScorePanel: View {
    let d: Dashboard

    var body: some View {
        HStack(spacing: 28) {
            ScoreRing(score: d.kpis.sleepScore)
                .frame(width: 124, height: 124)
            VStack(alignment: .leading, spacing: 10) {
                Text("Sleep Score")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                if let change = d.kpis.sleepScoreChange {
                    Label("\(ChangeLabel.signed(Double(change))) vs the 14 nights before",
                          systemImage: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(change >= 0 ? Theme.upOnDark : Theme.stageColor("Awake"))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background((change >= 0 ? Theme.up : Theme.down).opacity(0.22), in: Capsule())
                }
                Text(ScoreText.message(d.kpis.sleepScore, d.kpis.sleepScoreParts))
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 330, alignment: .leading)
            Rectangle().fill(Theme.panelStroke).frame(width: 1).padding(.vertical, 4)
            StageMix(stages: d.stages)
        }
        .fixedSize(horizontal: false, vertical: true)   // as tall as its content; the divider follows
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frosted(RoundedRectangle(cornerRadius: Theme.panelRadius))
    }
}

struct ScoreRing: View {
    let score: Int?

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.10), lineWidth: 12)
            Circle()
                .trim(from: 0, to: Double(score ?? 0) / 100)
                .stroke(Theme.ring, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(score.map(String.init) ?? "—").font(.system(size: 42, weight: .semibold))
                Text("/100").font(.system(size: 13, weight: .medium)).opacity(0.6)
            }
            .foregroundStyle(.white)
            .monospacedDigit()
        }
        .padding(6)
    }
}

/// Plain-language reading of the score: a headline from its band, and the
/// part with the most room to improve (from the backend's score parts).
enum ScoreText {
    static func message(_ score: Int?, _ parts: ScoreParts?) -> String {
        guard let score, let parts else { return "Not enough nights in this period for a score." }
        let headline = score >= 85 ? "Great sleep!" : score >= 70 ? "Good sleep." : score >= 50 ? "Fair sleep." : "A rough stretch."
        let weakest = [("timing", parts.timing), ("consistency", parts.consistency),
                       ("stages", parts.stages), ("duration", parts.duration)].min { $0.1 < $1.1 }!
        guard weakest.1 < 0.9 else {
            return headline + " Timing, schedule, stages and duration are all close to target."
        }
        let tip = [
            "timing": "Bed and wake times are furthest from target (11:30 PM and 6:30 AM).",
            "consistency": "A steadier bed and wake schedule would help most.",
            "stages": "Your mix of sleep stages has the most room to improve.",
            "duration": "More time asleep would help most (target 7.5 hours).",
        ][weakest.0]!
        return headline + " " + tip
    }
}

/// "Sleep Stages": a stacked bar of the window's stage shares and a legend.
struct StageMix: View {
    let stages: [StageShare]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 24) {
                Text("Sleep Stages")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                bar.frame(maxWidth: 280).frame(height: 14)
            }
            Grid(alignment: .leading, horizontalSpacing: 40, verticalSpacing: 12) {
                GridRow { item("Deep"); item("Light") }
                GridRow { item("REM"); item("Awake") }
            }
        }
        .frame(maxWidth: .infinity)
        .environment(\.colorScheme, .dark)   // the header is dark in both appearances
    }

    private func share(_ name: String) -> Double {
        stages.first { $0.stage == name }?.share ?? 0
    }

    private var bar: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(Theme.stages, id: \.name) { stage in
                    Rectangle()
                        .fill(stage.color)
                        .frame(width: max(0, geo.size.width - 6) * share(stage.name))
                }
            }
            .clipShape(Capsule())
        }
    }

    private func item(_ name: String) -> some View {
        HStack(spacing: 10) {
            Swatch(color: Theme.stageColor(name), size: 12)
            Text(name).font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.85))
            Spacer(minLength: 24)
            Text(Theme.percent(share(name)))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .frame(width: 170)
    }
}

// ── Page ──────────────────────────────────────────────────────────────────────

struct Page: View {
    let d: Dashboard

    var body: some View {
        let k = d.kpis
        VStack(spacing: Theme.gap) {
            HStack(spacing: Theme.gap) {
                StatTile(title: "Daily Average Steps", badge: Theme.steps,
                         value: k.avgSteps.map { $0.formatted() }, unit: nil,
                         change: k.avgStepsChangePct.map {
                             ChangeLabel(text: ChangeLabel.signed($0) + "% " + versus, change: $0, higherIsBetter: true)
                         })
                StatTile(title: "Average Sleep", badge: Theme.sleep,
                         value: k.avgSleepH.map { $0.formatted(.number.precision(.fractionLength(1))) }, unit: "hrs",
                         change: k.avgSleepHChange.map {
                             ChangeLabel(text: ChangeLabel.signed($0, decimals: 1) + " hrs " + versus, change: $0,
                                         higherIsBetter: true)
                         })
                StatTile(title: "Resting Heart Rate", badge: Theme.heart,
                         value: k.avgRestingHr.map(String.init), unit: "bpm",
                         change: k.avgRestingHrChange.map {
                             ChangeLabel(text: ChangeLabel.signed(Double($0)) + " bpm " + versus, change: Double($0),
                                         higherIsBetter: false)
                         })
                StatTile(title: "Weight", badge: Theme.scale,
                         value: k.weight.map { $0.formatted(.number.precision(.fractionLength(1))) }, unit: d.units,
                         change: k.weightChange.map {
                             ChangeLabel(text: ChangeLabel.signed($0, decimals: 1) + " \(d.units) " + across, change: $0,
                                         higherIsBetter: nil)
                         })
            }
            .fixedSize(horizontal: false, vertical: true)
            ChartPager(d: d)
        }
        .padding(Theme.inset)
    }

    /// "vs April" / "vs the 30 days before".
    private var versus: String {
        guard d.selection != "last30", let start = Calendar.current.date(byAdding: .month, value: -1, to: d.window.start)
        else { return "vs the 30 days before" }
        return "vs " + start.formatted(.dateTime.month(.wide))
    }

    private var across: String {
        d.selection == "last30" ? "over 30 days" : "this month"
    }
}

/// The charts the pager steps through, in order; Weight only when the export
/// has body data.
enum ChartPage: Hashable {
    case sleep, workouts, calories, weight

    static func available(in d: Dashboard?) -> [ChartPage] {
        d?.weight == nil ? [.sleep, .workouts, .calories] : [.sleep, .workouts, .calories, .weight]
    }

    var title: String {
        switch self {
        case .sleep: "Sleep Breakdown"
        case .workouts: "Workout Sessions"
        case .calories: "Calories Burned"
        case .weight: "Weight Trend"
        }
    }

    var icon: String {
        switch self {
        case .sleep: "moon.fill"
        case .workouts: "figure.run"
        case .calories: "flame.fill"
        case .weight: "scalemass.fill"
        }
    }
}

/// One chart at a time, filling the page below the tiles. The ‹ › buttons on
/// the card's edges (or ⌘[ ⌘]) step through them, wrapping round; the dots
/// below show where you are and jump straight to a chart.
struct ChartPager: View {
    let d: Dashboard
    @Environment(DashboardModel.self) private var model

    static let slide = Animation.easeInOut(duration: 0.3)

    var body: some View {
        let pages = ChartPage.available(in: d)
        let page = pages[min(model.chart, pages.count - 1)]
        VStack(spacing: 14) {
            ZStack {
                card(page)
                    .id(page)
                    .transition(.push(from: model.chartForward ? .trailing : .leading))
            }
            .padding(12).clipped().padding(-12)   // clip the slide, not the card's shadow
            .overlay(alignment: .leading) { arrow(forward: false).offset(x: -17) }
            .overlay(alignment: .trailing) { arrow(forward: true).offset(x: 17) }
            dots(pages, current: page)
        }
    }

    @ViewBuilder private func card(_ page: ChartPage) -> some View {
        switch page {
        case .sleep:
            ChartCard(page.title, icon: page.icon) {
                if let night = d.hypnogram { NightStepper(night: night) }
            } content: {
                if let night = d.hypnogram {
                    HypnogramChart(night: night)
                } else {
                    Text("No sleep recorded in this period.").font(.system(size: 13)).foregroundStyle(Theme.sub)
                }
            }
        case .workouts:
            ChartCard(page.title, icon: page.icon) {
                Caption(WorkoutsChart.caption(d.workouts))
            } content: {
                WorkoutsChart(workouts: d.workouts)
            }
        case .calories:
            ChartCard(page.title, icon: page.icon) {
                Caption(CaloriesChart.caption(d.calories))
            } content: {
                CaloriesChart(days: d.calories, window: d.window)
            }
        case .weight:
            if let weight = d.weight {
                ChartCard(page.title, icon: page.icon) {
                    Caption(WeightChart.caption(weight, units: d.units))
                } content: {
                    WeightChart(points: weight, window: d.window, units: d.units)
                }
            }
        }
    }

    private func arrow(forward: Bool) -> some View {
        Button {
            withAnimation(Self.slide) { model.stepChart(forward: forward) }
        } label: {
            Image(systemName: forward ? "chevron.right" : "chevron.left")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 34, height: 34)
                .background(Theme.card, in: Circle())
                .overlay(Circle().strokeBorder(Theme.border))
                .shadow(color: Theme.night.opacity(0.10), radius: 6, y: 2)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(forward ? "Next chart (⌘])" : "Previous chart (⌘[)")
    }

    private func dots(_ pages: [ChartPage], current: ChartPage) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(pages.enumerated()), id: \.element) { i, p in
                Button {
                    withAnimation(Self.slide) { model.showChart(i) }
                } label: {
                    Capsule()
                        .fill(p == current ? Theme.blue : Theme.sub.opacity(0.3))
                        .frame(width: p == current ? 20 : 7, height: 7)
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(p.title)
            }
        }
    }
}

/// A KPI: a colored icon badge and title, the value with its unit, and its change.
struct StatTile: View {
    let title: String
    let badge: (icon: String, color: Color)
    let value: String?
    let unit: String?
    let change: ChangeLabel?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: badge.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(badge.color.gradient, in: Circle())
                Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.sub)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value ?? "—").font(.system(size: 30, weight: .semibold)).foregroundStyle(Theme.ink)
                if let unit, value != nil {
                    Text(unit).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.sub)
                }
            }
            .monospacedDigit()
            if let change {
                change
            } else {
                Text("No earlier data to compare").font(.system(size: 12)).foregroundStyle(Theme.sub)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 18)
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

struct Caption: View {
    let text: String?

    init(_ text: String?) { self.text = text }

    var body: some View {
        if let text { Text(text).font(.system(size: 12)).foregroundStyle(Theme.sub) }
    }
}

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

// ── First launch / unreadable folder ──────────────────────────────────────────

struct FolderPrompt: View {
    let title: String
    let message: String
    @AppStorage(Pref.folder) private var folder = ""
    @State private var choosing = false

    var body: some View {
        ZStack {
            HeaderBackground()
            VStack(spacing: 16) {
                AayuLogo(size: 112)
                Text(title)
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(.white)
                Text(message)
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
                HStack(spacing: 10) {
                    Button { choosing = true } label: {
                        Text("Choose Zepp Folder")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.night)
                            .padding(.horizontal, 32)
                            .frame(height: 50)
                            .background(.white, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    SettingsLink {
                        Image(systemName: "gearshape")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 50, height: 50)
                            .frosted(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Settings (⌘,)")
                }
                .padding(.top, 10)
            }
            .padding(40)
        }
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { folder = url.path }
        }
    }
}
