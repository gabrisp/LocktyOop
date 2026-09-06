import Foundation

/// What each rule did, day by day.
///
/// The enforcement record keeps one day and forgets it at midnight -- deliberately, so
/// nothing has to go round resetting counters. That is right for enforcing a limit and
/// useless for reading one back: "how did this go last week" had no answer at all, and the
/// rules screen had to say so rather than draw a flat line.
///
/// So the day is copied here before it is lost. Written by the app whenever it reads the
/// limits, and by the monitor extension the moment a budget is spent -- which is the one
/// event that must survive a day the app is never opened.
nonisolated struct RuleHistory: Codable, Hashable {
    /// One rule on one day.
    nonisolated struct DayRecord: Codable, Hashable {
        /// How many times its apps were opened.
        var opens: Int
        /// How long was spent in them, in seconds.
        var seconds: TimeInterval
        /// Whether the rule actually stopped anything that day.
        var wasReached: Bool

        init(opens: Int = 0, seconds: TimeInterval = 0, wasReached: Bool = false) {
            self.opens = opens
            self.seconds = seconds
            self.wasReached = wasReached
        }
    }

    /// Rule id, then day key, then what happened.
    var days: [UUID: [String: DayRecord]]

    init(days: [UUID: [String: DayRecord]] = [:]) {
        self.days = days
    }

    static let empty = RuleHistory()

    /// How far back it keeps. Ninety days: enough for a month chart and the fortnight
    /// behind it, and small enough to stay a file you can decode without thinking.
    static let historyDays = 90

    /// The same day key the enforcement record uses, for the same reason: it has to be
    /// readable from the extensions and mean "that day" after a timezone change.
    nonisolated static func dayKey(for date: Date = Date()) -> String {
        RuleEnforcementState.dayKey(for: date)
    }

    nonisolated func record(for ruleID: UUID, on date: Date = Date()) -> DayRecord? {
        days[ruleID]?[Self.dayKey(for: date)]
    }

    /// Writes a day down, replacing whatever was there.
    ///
    /// Replacing rather than adding: this is called repeatedly through the day with the
    /// figures as they stand, and adding would count the same morning several times over.
    /// The one exception is the flag -- a limit that was reached at four o'clock was
    /// reached, whatever a later reading says.
    nonisolated mutating func write(_ record: DayRecord, for ruleID: UUID, on date: Date = Date()) {
        let key = Self.dayKey(for: date)
        var byDay = days[ruleID] ?? [:]
        var next = record
        next.wasReached = record.wasReached || (byDay[key]?.wasReached ?? false)
        next.opens = max(record.opens, byDay[key]?.opens ?? 0)
        next.seconds = max(record.seconds, byDay[key]?.seconds ?? 0)
        byDay[key] = next
        days[ruleID] = byDay
    }

    /// Marks a rule as having stopped something today, without touching its figures.
    ///
    /// For the extension, which knows the budget is spent and nothing else: it has no
    /// report to read and must not overwrite what the app wrote with zeroes.
    nonisolated mutating func markReached(_ ruleID: UUID, on date: Date = Date()) {
        let key = Self.dayKey(for: date)
        var byDay = days[ruleID] ?? [:]
        var record = byDay[key] ?? DayRecord()
        record.wasReached = true
        byDay[key] = record
        days[ruleID] = byDay
    }

    /// The run of days behind a date, oldest first, with nothing for the days that have
    /// nothing.
    nonisolated func series(
        for ruleID: UUID,
        days count: Int,
        endingOn date: Date = Date(),
        calendar: Calendar = .current
    ) -> [(date: Date, record: DayRecord?)] {
        stride(from: count - 1, through: 0, by: -1).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: date)) else {
                return nil
            }
            return (day, record(for: ruleID, on: day))
        }
    }

    /// Drops rules that are gone and days past the window.
    nonisolated mutating func prune(keeping ruleIDs: Set<UUID>, on date: Date = Date()) {
        let calendar = Calendar.current
        let oldest = calendar.date(byAdding: .day, value: -Self.historyDays, to: calendar.startOfDay(for: date))
            .map { Self.dayKey(for: $0) } ?? ""

        days = days
            .filter { ruleIDs.contains($0.key) }
            .mapValues { byDay in byDay.filter { $0.key >= oldest } }
    }
}
