import Foundation

/// Plain-language reading of the score: a headline from its band, and the
/// part with the most room to improve (from the backend's score parts).
/// `bedtime` and `wakeTime` are the targets the score was timed against.
enum ScoreText {
    static func message(_ score: Int?, _ parts: ScoreParts?, bedtime: ClockTime, wakeTime: ClockTime,
                        locale: Locale = .autoupdatingCurrent) -> String {
        guard let score, let parts else { return "Not enough nights in this period for a score." }
        let headline = score >= 85 ? "Great sleep!" : score >= 70 ? "Good sleep." : score >= 50 ? "Fair sleep." : "A rough stretch."
        let bed = Theme.clockTime(bedtime, locale: locale), wake = Theme.clockTime(wakeTime, locale: locale)
        // Each part with its tip; on a tie the earlier part wins.
        var tips = [
            (parts.timing, "Bed and wake times are furthest from your targets (\(bed) and \(wake))."),
            (parts.consistency, "A steadier bed and wake schedule would help most."),
            (parts.stages, "Your mix of sleep stages has the most room to improve."),
            (parts.duration, "More time asleep would help most (target 7.5 hours)."),
        ]
        if let awakenings = parts.awakenings {
            tips.append((awakenings, "Waking less often in the night would help most."))
        }
        guard let weakest = tips.min(by: { $0.0 < $1.0 }), weakest.0 < 0.9 else {
            return headline + (parts.awakenings == nil
                ? " Timing, schedule, stages and duration are all close to target."
                : " Timing, schedule, stages, duration and awakenings are all close to target.")
        }
        return headline + " " + weakest.1
    }
}
