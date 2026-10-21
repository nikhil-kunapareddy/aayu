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
