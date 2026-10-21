/// Plain-language reading of the score: a headline from its band, and the
/// part with the most room to improve (from the backend's score parts).
enum ScoreText {
    static func message(_ score: Int?, _ parts: ScoreParts?) -> String {
        guard let score, let parts else { return "Not enough nights in this period for a score." }
        let headline = score >= 85 ? "Great sleep!" : score >= 70 ? "Good sleep." : score >= 50 ? "Fair sleep." : "A rough stretch."
        // Each part with its tip; on a tie the earlier part wins.
        let tips = [
            (parts.timing, "Bed and wake times are furthest from target (11:30 PM and 6:30 AM)."),
            (parts.consistency, "A steadier bed and wake schedule would help most."),
            (parts.stages, "Your mix of sleep stages has the most room to improve."),
            (parts.duration, "More time asleep would help most (target 7.5 hours)."),
        ]
        guard let weakest = tips.min(by: { $0.0 < $1.0 }), weakest.0 < 0.9 else {
            return headline + " Timing, schedule, stages and duration are all close to target."
        }
        return headline + " " + weakest.1
    }
}
