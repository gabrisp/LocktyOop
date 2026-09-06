import Foundation

/// A run of days you kept.
///
/// The rule is deliberately winnable two ways, and both are things you actually did
/// rather than things that happened to you:
///
/// - a routine ran, or
/// - the day came in under your own recent average for screen time.
///
/// One rule would be wrong for half the people using this. Somebody who blocks apps on a
/// schedule keeps the streak by running their routines; somebody who only sets limits
/// keeps it by having the quieter day. Neither is asked to do the other's thing.
///
/// Today is never counted against you. A streak that breaks at 00:01 because the day has
/// not happened yet is a streak that punishes you for waking up -- so an unearned today
/// leaves yesterday's run standing, and earning it extends the run.
struct StreakSummary: Equatable {
    /// Days in a row up to and including today.
    var current: Int
    /// The longest run there has ever been.
    var best: Int
    /// Whether today is already earned.
    var isTodayEarned: Bool
    /// How the last fortnight went, oldest first. For the row of marks in the sheet.
    var recentDays: [Bool]
    /// How many of the earned days were earned by a routine running.
    var daysWithRoutine: Int
    /// And how many by a lighter day than usual.
    var daysUnderUsual: Int

    static let empty = StreakSummary(
        current: 0,
        best: 0,
        isTodayEarned: false,
        recentDays: [],
        daysWithRoutine: 0,
        daysUnderUsual: 0
    )
}

struct StreakCalculator {
    private let appGroupStore: AppGroupStore

    /// How far back it looks. Ninety days is long enough for any streak anybody has, and
    /// short enough to be ninety cached file reads rather than a year of them.
    private let horizon = 90

    init(appGroupStore: AppGroupStore = AppGroupStore()) {
        self.appGroupStore = appGroupStore
    }

    func summary(routineDays: Set<DayKey>, calendar: Calendar = .current, now: Date = Date()) -> StreakSummary {
        let today = calendar.startOfDay(for: now)

        // Every cached day, read once, keyed by the day it belongs to. Asking for them
        // one at a time costs a scan of the whole archive for each day that has no file
        // of its own -- and looking ninety days back, most of them will not.
        let usageByDay = Dictionary(
            appGroupStore.loadAllScreenTimeReportSnapshots().map { ($0.day.id, $0.totalActivityDuration) },
            uniquingKeysWith: { first, _ in first }
        )

        // Each day, oldest first, with whether it was earned.
        var days: [(date: Date, earned: Bool, byRoutine: Bool, byUsage: Bool)] = []

        for offset in stride(from: horizon, through: 0, by: -1) {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let key = DayKey(date: date, calendar: calendar)

            let byRoutine = routineDays.contains(key)
            let byUsage = wasLighterThanUsual(date, usageByDay: usageByDay, calendar: calendar)
            days.append((date, byRoutine || byUsage, byRoutine, byUsage))
        }

        guard !days.isEmpty else { return .empty }

        let isTodayEarned = days.last?.earned ?? false

        // Counting back from today, or from yesterday when today has not been earned yet.
        var current = 0
        for day in days.reversed() {
            if calendar.isDate(day.date, inSameDayAs: today), !day.earned { continue }
            guard day.earned else { break }
            current += 1
        }

        var best = 0
        var run = 0
        for day in days {
            run = day.earned ? run + 1 : 0
            best = max(best, run)
        }

        return StreakSummary(
            current: current,
            best: max(best, current),
            isTodayEarned: isTodayEarned,
            recentDays: days.suffix(14).map(\.earned),
            daysWithRoutine: days.filter(\.byRoutine).count,
            daysUnderUsual: days.filter { $0.byUsage && !$0.byRoutine }.count
        )
    }

    /// Whether a day came in under the fortnight before it.
    ///
    /// Against the run-up to *that* day rather than against a fixed target, so the bar
    /// moves with you: a lighter day is lighter than you have been, which is the only
    /// version of it worth keeping a streak over. Three days of history at minimum, for
    /// the same reason every other comparison in the app needs it.
    private func wasLighterThanUsual(
        _ date: Date,
        usageByDay: [String: TimeInterval],
        calendar: Calendar
    ) -> Bool {
        let usage = usageByDay[DayKey(date: date, calendar: calendar).id] ?? 0
        guard usage > 0 else { return false }

        var earlier: [TimeInterval] = []
        for offset in 1...14 {
            guard let previous = calendar.date(byAdding: .day, value: -offset, to: date),
                  let earlierUsage = usageByDay[DayKey(date: previous, calendar: calendar).id],
                  earlierUsage > 0
            else { continue }
            earlier.append(earlierUsage)
        }

        guard earlier.count >= 3 else { return false }
        return usage < earlier.reduce(0, +) / Double(earlier.count)
    }
}
