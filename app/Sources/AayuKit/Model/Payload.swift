import Foundation

// What the backend sends. Shapes mirror backend/aayu_backend/series.py
// (`dashboard()`) and server.py (`status()`); keys arrive in snake_case.

struct Dashboard: Decodable, Sendable {
    let selection: String        // 'YYYY-MM' or 'last30'
    let options: [String]        // picker entries, newest → oldest
    let window: DateWindow
    let units: String            // "lbs" or "kg"
    let kpis: KPIs
    let stages: [StageShare]          // stage shares across the window (hero bar)
    let hypnogram: Hypnogram?         // one night, for Sleep Breakdown
    let workouts: Workouts
    let calories: [CalorieDay]
    let weight: [WeightPoint]?   // nil when the export has no body data
}

struct DateWindow: Decodable, Sendable {
    let start: Date   // first day shown (midnight)
    let end: Date     // last day shown (midnight)
}

/// Header numbers for the window. Changes compare with the span before it
/// (the previous month or 30 days); the score with the 14 nights before.
struct KPIs: Decodable, Sendable {
    let sleepScore: Int?
    let sleepScoreChange: Int?
    let sleepScoreParts: ScoreParts?
    let avgSteps: Int?
    let avgStepsChangePct: Double?
    let avgSleepH: Double?
    let avgSleepHChange: Double?
    let avgRestingHr: Int?
    let avgRestingHrChange: Int?
    let weight: Double?          // last weigh-in by the window's end, in the dashboard's units
    let weightChange: Double?    // across the window's weigh-ins
}

/// The sleep score's parts, each 0–1 (1 = on target).
struct ScoreParts: Decodable, Sendable {
    let timing: Double
    let consistency: Double
    let stages: Double
    let duration: Double
}

/// One night's stages over time. `nights` lists every night in the window
/// ('YYYY-MM-DD', oldest first) so the card can step between them.
struct Hypnogram: Decodable, Sendable {
    let night: String
    let nights: [String]
    let start: Date   // bedtime, or the first stage minute if earlier
    let end: Date     // wake time, or the end of the last stage minute if later
    let segments: [StageSpan]
    let totals: [StageShare]
    let asleep: Int     // minutes in a sleep stage
    let duration: Int   // start to end, minutes
}

struct StageSpan: Decodable, Sendable, Identifiable {
    let stage: String
    let start: Date
    let end: Date
    var id: Date { start }
}

/// A stage's share of sleep minutes (across the window, or one night).
struct StageShare: Decodable, Sendable, Identifiable {
    let stage: String
    let minutes: Int
    let share: Double   // 0…1
    var id: String { stage }
}

struct Workouts: Decodable, Sendable {
    let start: Date   // axis start (two months back)
    let end: Date
    let weeks: [WorkoutWeek]
}

struct WorkoutWeek: Decodable, Sendable, Identifiable {
    let week: Date    // Monday the week starts
    let type: String  // "Strength" or "Running"
    let count: Int
    var id: String { "\(week.timeIntervalSince1970)-\(type)" }
}

struct CalorieDay: Decodable, Sendable, Identifiable {
    let date: Date
    let calories: Double
    let avg7: Double
    let marker: Bool  // draw a dot here (~14 per window)
    var id: Date { date }
}

struct WeightPoint: Decodable, Sendable, Identifiable {
    let date: Date
    let value: Double
    let marker: Bool
    var id: Date { date }
}

/// A folder's contents, for the Settings status line.
struct FolderStatus: Decodable, Sendable {
    let exists: Bool
    let found: [String]     // e.g. ["Sleep", "Activity", …]
    let total: Int
    let error: String?      // set when this folder is open and failed to load
    let errorCode: String?  // `error`'s code (AppError.Code's raw values)

    /// `error` as an AppError, if there is one.
    var failure: AppError? {
        error.map { AppError.backend(rawCode: errorCode, message: $0) }
    }
}
