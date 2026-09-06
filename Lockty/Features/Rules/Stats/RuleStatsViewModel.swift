import Combine
import Foundation
import SwiftUI

/// One rule and how it has actually been going.
struct RuleStat: Identifiable, Hashable {
    let id: UUID
    let name: String
    let kind: RuleKind
    let symbolName: String
    /// Its own colour, where it has one.
    ///
    /// A schedule *is* a mode: it was given an icon and a colour when it was written, and
    /// that is how it is recognised on every other screen. A limit was given neither --
    /// there is nothing to choose -- so it stays grey, and a colour invented for it here
    /// would be this screen claiming something the rule never said.
    let color: RoutineColor?
    /// How many times it ran in the period on screen.
    let runs: Int
    /// How long it was on, in total.
    let duration: TimeInterval
    /// Whether it is running right now.
    let isRunning: Bool
    /// Whether it is on hold, and until when.
    let pausedUntil: Date?
    /// What its chart is counting, said in a sentence.
    let chartCaption: String
    /// One figure per day across the period, for the chart.
    let runsByDay: [ChartDay]

    struct ChartDay: Hashable {
        let date: Date
        let value: Double
    }

    /// What it is drawn in: its own colour, or plain grey for the ones that have none.
    var tint: Color {
        color.map(LocktyColors.routine) ?? LocktyColors.neutral
    }

    /// Whether it has a colour of its own at all. What is lit around it depends on this:
    /// light added to a grey pill on a pale page is nothing anybody can see.
    var hasOwnColor: Bool { color != nil }

    /// "3 times · 2 h 10 m", or what is standing in its way.
    var detail: String {
        if let pausedUntil {
            return "Paused until \(LocktyDateFormatting.shortDayAndTime(pausedUntil))"
        }

        guard runs > 0 else { return kind == .schedule ? "Not run" : "Never reached" }

        let times = kind == .schedule
            ? (runs == 1 ? "1 time" : "\(runs) times")
            : (runs == 1 ? "Reached once" : "Reached \(runs) times")

        guard duration >= 60 else { return times }
        return "\(times) · \(LocktyDurationFormatter.abbreviated(duration))"
    }
}

/// Which heading a rule sits under.
///
/// By kind, not by whether it has been done: a rule is not finished or unfinished, it is a
/// schedule, a sitting, or a cap on the day -- and those are three different promises.
enum RuleStatSection: String, CaseIterable, Identifiable {
    case schedule
    case session
    case limits

    var id: String { rawValue }

    var title: String {
        switch self {
        case .schedule: "Schedule"
        case .session: "Session"
        case .limits: "Limits"
        }
    }

    func contains(_ kind: RuleKind) -> Bool {
        switch self {
        case .schedule: kind == .schedule
        case .session: kind == .sessionDurationLimit
        case .limits: kind == .openCountLimit || kind == .dailyUsageLimit
        }
    }
}

/// Everything the rules screens read.
///
/// The same shape as the objectives model, deliberately: a period, a list of things, and
/// per-thing history. The two screens answer the same kind of question -- what did I set
/// myself, and how has it actually gone -- so they are built alike rather than each
/// inventing its own.
///
/// What it can honestly say is decided by what is written down. Modes have a real history:
/// every run is stored, with when it started and when it ended. Limits do not -- Screen
/// Time tells the extension a budget is spent and nothing keeps yesterday's -- so a limit
/// reports what is true now and no further back.
@MainActor
final class RuleStatsViewModel: ObservableObject {
    @Published private(set) var stats: [RuleStat] = []
    @Published private(set) var isLoading = false

    /// What the last load was for, and when.
    ///
    /// Today asks for this on every scene change and every sheet that closes, and each ask
    /// is a Core Data fetch of the day's executions plus two App Group reads. Repeating it
    /// a second after the last one cannot produce a different answer, so it does not.
    private var lastLoadKey: String?
    private var lastLoadedAt: Date?

    private let repository: RuleRepository
    private let executionRepository: RoutineExecutionRepository
    private let routineEngine: RoutineEngine
    private let appGroupStore: AppGroupStore

    init(
        repository: RuleRepository,
        executionRepository: RoutineExecutionRepository,
        routineEngine: RoutineEngine,
        appGroupStore: AppGroupStore
    ) {
        self.repository = repository
        self.executionRepository = executionRepository
        self.routineEngine = routineEngine
        self.appGroupStore = appGroupStore
    }

    /// How many rules ran in the period on screen. The figure the card on Today shows.
    var ranCount: Int {
        stats.filter { $0.runs > 0 }.count
    }

    var runningNow: Int {
        stats.filter(\.isRunning).count
    }

    func stats(in section: RuleStatSection) -> [RuleStat] {
        stats.filter { section.contains($0.kind) }
    }

    /// Read over a range, not a cadence.
    ///
    /// `UsagePeriod`, not `ObjectivePeriod`: an objective is counted *daily* or *weekly* --
    /// that is a property of the objective -- while a rule is simply asked about a day, a
    /// week or a month. Same three words, opposite meanings, and the segment was saying
    /// the wrong one.
    func load(period: UsagePeriod, anchor: Date, days: Int, force: Bool = false) async {
        let key = "\(period.rawValue)-\(RuleEnforcementState.dayKey(for: anchor))-\(days)"

        if !force,
           key == lastLoadKey,
           let lastLoadedAt,
           Date().timeIntervalSince(lastLoadedAt) < 3 {
            return
        }

        lastLoadKey = key
        lastLoadedAt = Date()

        isLoading = true
        defer { isLoading = false }

        let calendar = Calendar.current
        let interval = Self.interval(for: period, anchor: anchor, calendar: calendar)

        let rules = (try? await repository.rules()) ?? []
        let executions = (try? await executionRepository.executions(from: interval.start, to: interval.end)) ?? []
        let pauses = appGroupStore.loadRulePauseState()
        let history = appGroupStore.loadRuleHistory()
        let runningIDs = Set(routineEngine.activeRoutines.map(\.routineID))

        let next = rules.map { rule -> RuleStat in
            // A schedule's history is its runs, which are stored as executions. A limit's
            // is the day file the app and the extension keep between them -- the
            // enforcement record itself is cleared every midnight.
            guard rule.kind != .schedule else {
                let mine = executions.filter { $0.routineID == rule.id }
                let duration = mine.reduce(0) { total, execution in
                    total + (execution.endedAt ?? Date()).timeIntervalSince(execution.startedAt)
                }

                // Its own icon and colour, off the mode it is: a calendar glyph in mint
                // says "this is a schedule", which is the one thing about it you already
                // know from the heading it sits under.
                let routine = rule.routineBridge

                return RuleStat(
                    id: rule.id,
                    name: rule.name,
                    kind: rule.kind,
                    symbolName: routine?.icon?.isEmpty == false ? routine!.icon! : "calendar",
                    color: routine?.color,
                    runs: mine.count,
                    duration: max(duration, 0),
                    isRunning: runningIDs.contains(rule.id),
                    pausedUntil: pauses.pauseEnd(for: rule.id),
                    chartCaption: "How many times it ran on each of the last \(days) days.",
                    runsByDay: Self.runsByDay(mine, days: days, endingOn: anchor, calendar: calendar)
                )
            }

            let series = history.series(for: rule.id, days: days, endingOn: anchor, calendar: calendar)
            let inPeriod = series.filter { interval.contains($0.date) || calendar.isDate($0.date, inSameDayAs: interval.start) }

            // A limit "ran" on a day it actually stopped something. Opening an app five
            // times under a cap of ten is the rule doing nothing, and counting it would
            // make every limit look like it fires daily.
            let firedDays = inPeriod.filter { $0.record?.wasReached == true }.count

            // What the chart draws depends on what the rule measures: opens for a count,
            // time for a budget. Drawing one against the other would be a chart with the
            // wrong units on it.
            let byOpens = rule.kind == .openCountLimit

            return RuleStat(
                id: rule.id,
                name: rule.name,
                kind: rule.kind,
                symbolName: Self.symbol(for: rule.kind),
                color: nil,
                runs: firedDays,
                duration: inPeriod.reduce(0) { $0 + ($1.record?.seconds ?? 0) },
                isRunning: false,
                pausedUntil: pauses.pauseEnd(for: rule.id),
                chartCaption: byOpens
                    ? "How many times its apps were opened on each of the last \(days) days."
                    : "How long was spent in its apps on each of the last \(days) days, in minutes.",
                runsByDay: series.map { entry in
                    RuleStat.ChartDay(
                        date: entry.date,
                        value: byOpens
                            ? Double(entry.record?.opens ?? 0)
                            : ((entry.record?.seconds ?? 0) / 60).rounded()
                    )
                }
            )
        }

        withAnimation(.smooth(duration: 0.3)) {
            stats = next.sorted { left, right in
                if left.isRunning != right.isRunning { return left.isRunning }
                if left.runs != right.runs { return left.runs > right.runs }
                return left.name < right.name
            }
        }
    }

    /// The window a period covers, around the anchor.
    private static func interval(for period: UsagePeriod, anchor: Date, calendar: Calendar) -> DateInterval {
        switch period {
        case .day:
            let start = calendar.startOfDay(for: anchor)
            return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: start) ?? start)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: anchor)
                ?? DateInterval(start: anchor, duration: 7 * 24 * 3600)
        case .month:
            return calendar.dateInterval(of: .month, for: anchor)
                ?? DateInterval(start: anchor, duration: 30 * 24 * 3600)
        }
    }

    private static func runsByDay(
        _ executions: [RoutineExecution],
        days: Int,
        endingOn day: Date,
        calendar: Calendar
    ) -> [RuleStat.ChartDay] {
        let counts = executions.reduce(into: [Date: Double]()) { result, execution in
            result[calendar.startOfDay(for: execution.startedAt), default: 0] += 1
        }

        return stride(from: days - 1, through: 0, by: -1).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: day)) else {
                return nil
            }
            return RuleStat.ChartDay(date: date, value: counts[date] ?? 0)
        }
    }

    private static func symbol(for kind: RuleKind) -> String {
        switch kind {
        case .schedule: "calendar"
        case .openCountLimit: "number.circle"
        case .dailyUsageLimit: "hourglass"
        case .sessionDurationLimit: "timer"
        }
    }

    // A colour per kind. Kept, unused: a schedule wears the colour it was given and a
    // limit wears none, so there was never a kind to colour.
    //
//    /// A kind's colour, from the same palette everything else is coloured from.
//    private static func color(for kind: RuleKind) -> RoutineColor {
//        switch kind {
//        case .schedule: .mint
//        case .openCountLimit: .amber
//        case .dailyUsageLimit: .sky
//        case .sessionDurationLimit: .violet
//        }
//    }
}
