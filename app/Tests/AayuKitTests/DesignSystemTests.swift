import AppKit
import Foundation
import SwiftUI
import Testing
@testable import AayuKit

@Suite("Design system")
struct DesignSystemTests {
    let en = Locale(identifier: "en_US")

    // ── Percentages ──────────────────────────────────────────────────────────
    static let percents: [([Double], [Int])] = [
        ([0.2, 0.22, 0.53, 0.05], [20, 22, 53, 5]),
        ([1.0 / 3, 1.0 / 3, 1.0 / 3], [34, 33, 33]),
        ([0.0625, 0.2375, 0.505, 0.195], [6, 24, 51, 19]),
        ([0, 0, 0, 0], [0, 0, 0, 0]),
        ([0, 1], [0, 100]),
    ]

    @Test(arguments: percents)
    func wholePercentsAddUpTo100(shares: [Double], expected: [Int]) {
        let whole = Theme.wholePercents(shares)
        #expect(whole == expected)
        if shares.contains(where: { $0 > 0 }) { #expect(whole.reduce(0, +) == 100) }
    }

    @Test func percentFormats() {
        #expect(Theme.percent(whole: 23, locale: en) == "23%")
        #expect(Theme.percent(0.234, decimals: 0, locale: en) == "23%")
        #expect(Theme.percent(0.234, locale: en) == "23.4%")
    }

    @Test func spokenDurations() {
        #expect(Theme.spokenDuration(minutes: 51, locale: en) == "51 minutes")
        #expect(Theme.spokenDuration(minutes: 72, locale: en) == "1 hour, 12 minutes")
    }

    @Test func sessionsArePluralised() {
        #expect(Theme.sessions(1) == "1 session")
        #expect(Theme.sessions(0) == "0 sessions")
        #expect(Theme.sessions(6) == "6 sessions")
    }

    // ── Layout maths ─────────────────────────────────────────────────────────
    @Test func segmentWidthsKeepSliversVisible() {
        let widths = Theme.segmentWidths([0.005, 0.2, 0.5, 0.295], total: 406, spacing: 2, minimum: 3)
        #expect(widths[0] == 3)
        #expect(abs(widths.reduce(0, +) - 400) < 0.001)   // 406 less three 2-pt gaps
        #expect(widths[2] > widths[3] && widths[3] > widths[1])
    }

    @Test func segmentWidthsSkipEmptyShares() {
        let widths = Theme.segmentWidths([0, 0.5, 0.5, 0], total: 102, spacing: 2, minimum: 3)
        #expect(widths == [0, 50, 50, 0])
        #expect(Theme.segmentWidths([0, 0], total: 100, spacing: 2, minimum: 3) == [0, 0])
    }

    static let widths: [(Double, LayoutClass)] = [(719, .narrow), (859, .narrow), (860, .compact), (1099, .compact),
                                                  (1100, .regular), (2400, .regular)]

    @Test(arguments: widths)
    func layoutClassFromWidth(width: Double, expected: LayoutClass) {
        #expect(LayoutClass(width: width) == expected)
    }

    // ── Axes ─────────────────────────────────────────────────────────────────
    /// lo, hi → the domain's ends and the step.
    static let axes: [[Double]] = [
        [300, 540, 300, 600, 100],   // calories
        [148.9, 153.4, 148, 154, 2], // weight
        [0, 4, 0, 4, 1],             // sessions
        [0, 5, 0, 6, 2],
        [150, 150, 150, 151, 0.5],   // a flat line still gets a step
    ]

    @Test(arguments: axes)
    func niceAxisSnapsToItsSteps(_ c: [Double]) {
        let axis = Theme.niceAxis(c[0], c[1])
        #expect(axis.domain == c[2]...c[3])
        #expect(axis.step == c[4])
        #expect(axis.domain.lowerBound <= c[0] && axis.domain.upperBound >= c[1])
    }

    @MainActor @Test func chartAxesEndOnGridlines() throws {
        let d = try Sample.dashboard()
        let calories = CaloriesChart.axis(d.calories)
        #expect(calories.domain.lowerBound.truncatingRemainder(dividingBy: calories.step) == 0)
        #expect(calories.domain.upperBound.truncatingRemainder(dividingBy: calories.step) == 0)
        let weight = WeightChart.axis(try #require(d.weight))
        #expect(weight.domain == 149...152)   // 151.5 and 150.0, half a pound of room, 1-lb steps
        #expect(WorkoutsChart.axis(d.workouts.weeks).domain == 0...3)
        #expect(WeightChart.caption(try #require(d.weight), units: "lbs") == "−1.5 lbs")   // a real minus
    }

    // ── Change labels ────────────────────────────────────────────────────────
    @MainActor @Test func changeLabelSpeaksDirectionAndTone() {
        let bpm = ChangeLabel(-2, higherIsBetter: false, locale: en) { "\($0) bpm vs April" }
        #expect(bpm.text == "−2 bpm vs April")
        #expect(bpm.accessibilityText == "down 2 bpm vs April, better")
        let steps = ChangeLabel(12.4, higherIsBetter: true, locale: en) { "\($0)% vs April" }
        #expect(steps.accessibilityText == "up 12% vs April, better")
        let none = ChangeLabel(0.2, higherIsBetter: true, locale: en) { "\($0) vs the 14 nights before" }
        #expect(none.text == "±0 vs the 14 nights before")
        #expect(none.accessibilityText == "unchanged, 0 vs the 14 nights before")
        let weight = ChangeLabel(-1.5, decimals: 1, higherIsBetter: nil, locale: en) { "\($0) lbs this month" }
        #expect(weight.accessibilityText == "down 1.5 lbs this month")
    }

    @MainActor @Test func scorePillUsesTheHeaderColours() {
        let worse = ChangeLabel(-3, higherIsBetter: true, surface: .header) { $0 }
        #expect(worse.tone == .worse)
        #expect(worse.color == Theme.headerDown)
        #expect(ChangeLabel(4, higherIsBetter: true, surface: .header) { $0 }.color == Theme.headerUp)
    }

    // ── Month menu ───────────────────────────────────────────────────────────
    @MainActor @Test func rangeMenuGroupsMonthsByYear() {
        let sections = RangeMenu.sections(["last30", "2026-02", "2026-01", "2025-12", "2025-11"])
        #expect(sections.map(\.title) == ["", "2026", "2025"])
        #expect(sections.map(\.options) == [["last30"], ["2026-02", "2026-01"], ["2025-12", "2025-11"]])
        #expect(RangeMenu.monthName("2026-05", locale: en, timeZone: Sample.utc) == "May")
    }

    // ── VoiceOver ────────────────────────────────────────────────────────────
    @Test func hypnogramDescriptorHasAPointPerStageRun() throws {
        let night = try #require(try Sample.dashboard().hypnogram)
        let descriptor = HypnogramDescriptor(night: night).makeChartDescriptor()
        #expect(descriptor.series.first?.dataPoints.count == night.segments.count)
        #expect(night.segments[1].minutes == 90)
        #expect(night.segments[1].spoken.hasSuffix("1 hour, 30 minutes"))
    }
}

/// WCAG 2.1 contrast for the palette, resolved in each appearance: text ≥ 4.5:1,
/// chart marks and controls ≥ 3:1, against what they sit on.
@MainActor @Suite("Contrast")
struct ContrastTests {
    private func rgb(_ color: Color, dark: Bool) throws -> (Double, Double, Double) {
        let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
        var out = (0.0, 0.0, 0.0)
        appearance.performAsCurrentDrawingAppearance {
            if let c = NSColor(color).usingColorSpace(.sRGB) {
                out = (Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent))
            }
        }
        return out
    }

    private func luminance(_ c: (Double, Double, Double)) -> Double {
        func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(c.0) + 0.7152 * linear(c.1) + 0.0722 * linear(c.2)
    }

    private func ratio(_ a: Color, _ b: Color, dark: Bool) throws -> Double {
        let la = luminance(try rgb(a, dark: dark)), lb = luminance(try rgb(b, dark: dark))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    @Test(arguments: [false, true])
    func textOnCards(dark: Bool) throws {
        for (name, color) in [("ink", Theme.ink), ("sub", Theme.sub), ("up", Theme.up), ("down", Theme.down)] {
            let r = try ratio(color, Theme.card, dark: dark)
            #expect(r >= 4.5, "\(name) on card is \(r):1")
        }
    }

    /// Against both ends of the header's gradient: night → dusk in Dark, dawn → haze in Light.
    @Test(arguments: [false, true])
    func textOnTheHeader(dark: Bool) throws {
        let ink = [("headerInk", Theme.headerInk), ("headerUp", Theme.headerUp), ("headerDown", Theme.headerDown)]
        for (name, color) in ink {
            for background in dark ? [Theme.night, Theme.dusk] : [Theme.dawn, Theme.haze] {
                let r = try ratio(color, background, dark: dark)
                #expect(r >= 4.5, "\(name) on the header is \(r):1")
            }
        }
    }

    @Test(arguments: [false, true])
    func marksAndControls(dark: Bool) throws {
        let onCard = [("Strength", Theme.navy), ("Running", Theme.sky), ("raw calories", Theme.mist),
                      ("7-day avg", Theme.blue), ("Deep", Theme.stageColor("Deep"))]
        for (name, color) in onCard {
            let r = try ratio(color, Theme.card, dark: dark)
            #expect(r >= 3, "\(name) on card is \(r):1")
        }
        let dot = try ratio(Theme.dot, Theme.page, dark: dark)
        #expect(dot >= 3, "inactive dot on page is \(dot):1")
    }

    @Test func appearancesDiffer() throws {
        let light = try rgb(Theme.card, dark: false).0, dark = try rgb(Theme.card, dark: true).0
        #expect(light != dark)
    }
}
