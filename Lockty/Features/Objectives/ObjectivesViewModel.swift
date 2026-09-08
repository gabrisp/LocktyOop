import Combine
import Foundation
import WidgetKit
import SwiftUI

/// Everything the objectives screens read and write.
///
/// One model rather than one per screen: the card on Today, the page behind it and the
/// friction that asks about them are all looking at the same short list, and three copies
/// of it would be three answers to "have I done my water yet".
@MainActor
final class ObjectivesViewModel: ObservableObject {
    @Published private(set) var objectives: [Objective] = []
    @Published private(set) var progress: ObjectiveProgressState = .empty

    private let appGroupStore: AppGroupStore
    /// Optional, because the friction step builds this model with nothing to hand. With
    /// no service the Health-backed objectives simply hold whatever was last read.
    private let healthService: HealthServicing?

    init(
        appGroupStore: AppGroupStore = AppGroupStore(),
        healthService: HealthServicing? = nil
    ) {
        self.appGroupStore = appGroupStore
        self.healthService = healthService
        load()
    }

    func load() {
        let stored = appGroupStore.loadObjectives().sorted { $0.createdAt < $1.createdAt }
        if objectives != stored { objectives = stored }

        // Pruned on the way in: progress is only kept for the period each objective is
        // currently in, so this is also what makes a new day start empty.
        let loaded = appGroupStore.loadObjectiveProgress()
        var pruned = loaded
        pruned.prune(keeping: objectives)

        if progress != pruned { progress = pruned }

        // Written only when the prune actually dropped something. This runs on every
        // appearance of Today, every return to the app, every closed sheet and every open
        // of the quick panel -- and it was encoding and writing the whole progress file
        // each time to save a copy identical to the one already there.
        if pruned != loaded {
            try? appGroupStore.saveObjectiveProgress(pruned)
        }

        Task { await refreshFromHealth() }
    }

    /// Reads the Health-backed objectives and files their values with the rest.
    ///
    /// Written into the same progress state as the tapped ones rather than kept apart:
    /// the card, the page, the friction and the Focus credit all read one place, and none
    /// of them should have to know which objectives are counted by a person and which by
    /// a phone.
    func refreshFromHealth() async {
        let measured = objectives.filter { $0.source.isMeasured }
        guard !measured.isEmpty else { return }

        var next = progress
        for objective in measured {
            let range = Self.range(for: objective.period)

            switch objective.source {
            case .steps:
                guard let healthService else { continue }
                let steps = (try? await healthService.stepCount(from: range.start, to: range.end)) ?? 0
                next.set(Double(steps), for: objective)
            case .sleep:
                guard let healthService else { continue }
                let hours = (try? await healthService.sleepHours(from: range.start, to: range.end)) ?? 0
                next.set(hours, for: objective)
            case .appUsage:
                next.set(appMinutes(for: objective), for: objective)
            case .screenTime:
                next.set(screenTimeMinutes(for: objective), for: objective)
            case .focusScore:
                guard let score = todaysFocusScore() else { continue }
                next.set(score, for: objective)
            case .manual:
                break
            }
        }

        guard next != progress else { return }
        write(next)
    }

    /// Minutes in one app over the objective's period, from the cached day snapshots.
    ///
    /// The same figure every usage screen shows, read from the same files -- so an
    /// objective about TikTok and the TikTok row on the breakdown cannot disagree.
    private func appMinutes(for objective: Objective) -> Double {
        guard let appID = objective.appID else { return 0 }

        let calendar = Calendar.current
        let days: Int = switch objective.period {
        case .daily: 1
        case .weekly: 7
        case .monthly: 30
        }

        var total: TimeInterval = 0
        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: Date()),
                  let snapshot = try? appGroupStore.loadScreenTimeReportSnapshot(for: DayKey(date: day))
            else { continue }

            total += snapshot.applications
                .first { $0.app.id == appID }?
                .totalActivityDuration ?? 0
        }

        return total / 60
    }

    /// Minutes on the phone altogether over the objective's period.
    ///
    /// The snapshot's own total rather than the sum of its apps: the two differ, because
    /// the total includes time Screen Time could not attribute to anything, and the figure
    /// on the Screen Time card is the total. An objective and the card it sits under
    /// disagreeing about the same day is worse than either number on its own.
    private func screenTimeMinutes(for objective: Objective) -> Double {
        let calendar = Calendar.current
        let days: Int = switch objective.period {
        case .daily: 1
        case .weekly: 7
        case .monthly: 30
        }

        var total: TimeInterval = 0
        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: Date()),
                  let snapshot = try? appGroupStore.loadScreenTimeReportSnapshot(for: DayKey(date: day))
            else { continue }

            total += snapshot.totalActivityDuration
        }

        return total / 60
    }

    /// Today's Focus score, or nil when the day's scores have not been worked out yet.
    ///
    /// Read from the App Group snapshot the pipeline leaves behind -- the same photograph
    /// the widget reads -- because the score comes out of Core Data, Screen Time and half
    /// a dozen calculators, and recomputing it here would be a second answer to the same
    /// question. Nil rather than zero when the snapshot is missing or belongs to another
    /// day: a "0% focus" that only means "not measured yet" would read as a kept ceiling.
    private func todaysFocusScore() -> Double? {
        guard let snapshot = appGroupStore.loadDailyScores(),
              snapshot.day == DayKey(date: Date()).id,
              let focus = snapshot.score(PrimaryMetricKind.focus.rawValue)
        else { return nil }

        return (focus.progress * 100).rounded()
    }

    /// The stretch a period covers, ending now.
    private static func range(for period: ObjectivePeriod, now: Date = Date()) -> (start: Date, end: Date) {
        var calendar = Calendar.current
        calendar.firstWeekday = 2

        let component: Calendar.Component = switch period {
        case .daily: .day
        case .weekly: .weekOfYear
        case .monthly: .month
        }

        let start = calendar.dateInterval(of: component, for: now)?.start
            ?? calendar.startOfDay(for: now)
        return (start, now)
    }

    // MARK: - Reading

    var completedCount: Int {
        objectives.filter { progress.isComplete($0) }.count
    }

    var allCompleted: Bool {
        !objectives.isEmpty && completedCount == objectives.count
    }

    /// The ones still to do, which is what a friction asks about.
    var outstanding: [Objective] {
        objectives.filter { !progress.isComplete($0) }
    }

    func value(of objective: Objective) -> Double {
        progress.value(for: objective)
    }

    /// The last so-many days of one objective, for its chart.
    func dailyValues(of objective: Objective, days: Int, endingOn day: Date = Date()) -> [(date: Date, value: Double)] {
        progress.dailyValues(for: objective, days: days, endingOn: day)
    }

    /// The run of days this objective has been kept, and the longest it has ever run.
    ///
    /// A day counts when it was a yes -- met, or in the case of a ceiling, stayed under.
    /// Days before the objective existed are not counted either way: a streak that starts
    /// the day you create something is the only honest kind.
    ///
    /// Today never breaks it. The day is not over, so an unmet objective at four in the
    /// afternoon leaves yesterday's run standing rather than ending it -- the same rule
    /// the app's own streak keeps.
    func streaks(of objective: Objective, days: Int = 90) -> (current: Int, longest: Int) {
        let calendar = Calendar.current
        let created = calendar.startOfDay(for: objective.createdAt)
        let values = dailyValues(of: objective, days: days)
            .filter { calendar.startOfDay(for: $0.date) >= created }

        guard !values.isEmpty else { return (0, 0) }

        func isKept(_ value: Double) -> Bool {
            objective.staysUnder ? value <= objective.target : value >= objective.target
        }

        var longest = 0
        var run = 0
        for entry in values {
            run = isKept(entry.value) ? run + 1 : 0
            longest = max(longest, run)
        }

        var current = 0
        for entry in values.reversed() {
            let isToday = calendar.isDateInToday(entry.date)
            if isToday, !isKept(entry.value) { continue }
            guard isKept(entry.value) else { break }
            current += 1
        }

        return (current, max(longest, current))
    }

    /// How many objectives of a period were finished in each of the periods behind us.
    ///
    /// One point per day for the daily ones, per week for the weekly, per month for the
    /// monthly -- each judged on its own key. It used to be one point per day whatever was
    /// being asked about, which is why the weekly tab drew a chart of how many *daily*
    /// objectives were finished: a weekly objective is not "done on Tuesday", it is done
    /// in a week, and giving it a Tuesday column invents a day for it.
    func completions(period: ObjectivePeriod, days: Int, endingOn day: Date = Date()) -> [(date: Date, value: Double)] {
        let counted = objectives.filter { $0.period == period }
        guard !counted.isEmpty else { return [] }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: day)

        // The start of every period the range touches, oldest first, each one once.
        var starts: [Date] = []
        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let start = periodStart(of: day, period: period, calendar: calendar)
            if starts.last != start { starts.append(start) }
        }

        return starts.map { start in
            let done = counted.filter { objective in
                let value = progress.values[objective.id]?[period.key(for: start, calendar: calendar)] ?? 0
                return value >= objective.target
            }
            return (start, Double(done.count))
        }
    }

    private func periodStart(of day: Date, period: ObjectivePeriod, calendar: Calendar) -> Date {
        switch period {
        case .daily:
            calendar.startOfDay(for: day)
        case .weekly:
            calendar.dateInterval(of: .weekOfYear, for: day)?.start ?? calendar.startOfDay(for: day)
        case .monthly:
            calendar.dateInterval(of: .month, for: day)?.start ?? calendar.startOfDay(for: day)
        }
    }

    /// The ones counted by the day, which are the only ones Today has anything to say
    /// about: a weekly objective on a screen about today answers a question nobody asked.
    var dailyObjectives: [Objective] {
        objectives.filter { $0.period == .daily }
    }

    func fraction(of objective: Objective) -> Double {
        progress.fraction(for: objective)
    }

    func isComplete(_ objective: Objective) -> Bool {
        progress.isComplete(objective)
    }

    // MARK: - Reading another day
    //
    // Everything above answers about now, which is right for a screen about now. Today can
    // be turned back to Tuesday, though, and asking these for Tuesday used to return
    // today's figures under Tuesday's heading -- so a day when everything was done showed
    // up empty. These take the day and read that day's key.

    func value(of objective: Objective, on day: Date) -> Double {
        progress.value(for: objective, on: day)
    }

    func fraction(of objective: Objective, on day: Date) -> Double {
        progress.fraction(for: objective, on: day)
    }

    func isComplete(_ objective: Objective, on day: Date) -> Bool {
        progress.isComplete(objective, on: day)
    }

    /// The daily objectives that existed on a given day.
    ///
    /// One made this morning was not something you failed to do last Tuesday, so it does
    /// not appear on last Tuesday's card at all.
    func dailyObjectives(on day: Date) -> [Objective] {
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)) ?? day
        return objectives.filter { $0.period == .daily && $0.createdAt < end }
    }

    /// "1.5 of 2 L", or "Done".
    func detail(for objective: Objective) -> String {
        guard !progress.isComplete(objective) else { return "Done" }
        return "\(objective.format(progress.value(for: objective))) of \(objective.format(objective.target))"
    }

    // MARK: - Writing

    /// Adds one step. The whole interaction of the card: a glass of water is a tap.
    ///
    /// Refused on the ones Health counts. Adding to a step count by hand is writing down
    /// a number you did not walk.
    func advance(_ objective: Objective) {
        guard !objective.source.isMeasured else { return }
        var next = progress
        next.add(objective.step, to: objective)
        write(next)
    }

    /// Takes one back, for the tap that was not meant.
    func stepBack(_ objective: Objective) {
        guard !objective.source.isMeasured else { return }
        var next = progress
        next.add(-objective.step, to: objective)
        write(next)
    }

    /// Fills it to the target in one go.
    func complete(_ objective: Objective) {
        guard !objective.source.isMeasured else { return }
        var next = progress
        let remaining = objective.target - next.value(for: objective)
        guard remaining > 0 else { return }
        next.add(remaining, to: objective)
        write(next)
    }

    /// Puts it back to nothing for this period, for the one marked done by mistake.
    func reset(_ objective: Objective) {
        guard !objective.source.isMeasured else { return }
        var next = progress
        next.set(0, for: objective)
        write(next)
    }

    func save(_ objective: Objective) {
        var stored = appGroupStore.loadObjectives()
        if let index = stored.firstIndex(where: { $0.id == objective.id }) {
            stored[index] = objective
        } else {
            stored.append(objective)
        }
        try? appGroupStore.saveObjectives(stored)
        load()
        reloadWidgets()
    }

    func delete(_ objective: Objective) {
        var stored = appGroupStore.loadObjectives()
        stored.removeAll { $0.id == objective.id }
        try? appGroupStore.saveObjectives(stored)
        load()
        reloadWidgets()
    }

    private func write(_ next: ObjectiveProgressState) {
        try? appGroupStore.saveObjectiveProgress(next)
        withAnimation(.smooth(duration: 0.3)) { progress = next }
        reloadWidgets()
    }

    /// The home screen is a second view of this list, and it does not watch the file.
    ///
    /// A glass logged in the app has to redraw the tile as well, or the widget goes on
    /// saying what was true when it was last drawn -- which is the one thing a widget
    /// cannot do and stay worth having.
    private func reloadWidgets() {
        WidgetCenter.shared.reloadTimelines(ofKind: ObjectiveWidgets.kind)
    }
}
