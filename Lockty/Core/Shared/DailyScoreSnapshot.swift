import Foundation

/// The day's three scores, written down where anything outside the app can read them.
///
/// The scores are computed by the pipeline out of Core Data, Screen Time and half a dozen
/// calculators -- none of which a widget can reach. So the app leaves the finished figures
/// in the App Group each time it works them out, and the widget reads that. It is a
/// photograph, not a source: nothing else may compute from it.
nonisolated struct DailyScoreSnapshot: Codable, Hashable {
    nonisolated struct Score: Codable, Hashable {
        /// `PrimaryMetricKind`'s raw value. A string rather than the enum: the enum lives
        /// in the app's own layer, and this file is read by a target that cannot see it.
        let kind: String
        let title: String
        /// "71%", "43" -- already formatted, because the formatting is a decision the app
        /// has already made and a widget disagreeing with the app about the same number
        /// is worse than a widget with no number.
        let displayValue: String
        /// How far round its rim goes, 0 to 1.
        let progress: Double
    }

    /// The day these belong to, as `DayKey.id`, so a snapshot from yesterday can be told
    /// from one from this morning.
    let day: String
    let updatedAt: Date
    let scores: [Score]
    /// Today's screen time, for the line under the scores.
    let screenTime: TimeInterval

    func score(_ kind: String) -> Score? {
        scores.first { $0.kind == kind }
    }
}
