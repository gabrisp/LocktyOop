import Foundation

/// One earlier day, reduced to the few figures a trend line needs.
nonisolated struct DailyTrendPoint: Equatable, Identifiable {
    let id: String
    let date: Date
    let usage: TimeInterval
    /// Hours with the screen effectively dark. The inverse reading of the same day.
    let untouchedHours: Int
    let pickups: Int
    let notifications: Int
}

/// The fortnight behind a day, from the cached snapshots.
///
/// From the App Group, never from Screen Time: a fortnight of report requests is a screen
/// nobody waits for, where a fortnight of file reads is a screen that opens. Days with no
/// snapshot are left out rather than drawn as zero -- a day Lockty was not opened is not a
/// day of no phone use, and a line dipping to the floor would say exactly that.
struct DailyTrendBuilder {
    private let appGroupStore: AppGroupStore

    init(appGroupStore: AppGroupStore = AppGroupStore()) {
        self.appGroupStore = appGroupStore
    }

    func trend(endingOn day: Date, days: Int = 14, calendar: Calendar = .current) -> [DailyTrendPoint] {
        let usageByDay = Dictionary(
            appGroupStore.loadAllScreenTimeReportSnapshots().map { ($0.day.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let today = calendar.startOfDay(for: day)

        return stride(from: days - 1, through: 0, by: -1).compactMap { offset -> DailyTrendPoint? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today),
                  let snapshot = usageByDay[DayKey(date: date, calendar: calendar).id],
                  snapshot.totalActivityDuration > 0
            else { return nil }

            // Hours are counted off the segments rather than off a stored figure: the
            // snapshot is the only record of when the day happened, and "untouched" is a
            // question about when, not how much.
            var usageByHour = [TimeInterval](repeating: 0, count: 24)
            for segment in snapshot.activitySegments {
                let hour = calendar.component(.hour, from: segment.dateInterval.start)
                guard (0..<24).contains(hour) else { continue }
                usageByHour[hour] += segment.totalActivityDuration
            }

            return DailyTrendPoint(
                id: snapshot.day.id,
                date: date,
                usage: snapshot.totalActivityDuration,
                untouchedHours: usageByHour.filter { $0 < 60 }.count,
                pickups: snapshot.activitySegments.reduce(0) { $0 + $1.pickups },
                notifications: snapshot.activitySegments.reduce(0) { $0 + $1.notifications }
            )
        }
    }
}
