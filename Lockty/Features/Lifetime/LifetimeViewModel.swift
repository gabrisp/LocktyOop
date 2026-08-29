import Foundation
import Combine

struct LifetimeTrend: Identifiable, Equatable {
    let id: String
    let title: String
    let value: String
    let detail: String
}

enum LifetimeLoadingState: Equatable {
    case loading
    case loaded
    case insufficient(String)
}

struct LifetimeState: Equatable {
    var loadingState: LifetimeLoadingState = .loading
    var reclaimedTime = "--"
    var baselineText = "Building your baseline"
    var currentPace = "--"
    var annualEquivalent = "--"
    var trends: [LifetimeTrend] = []
    var patterns: [String] = []
}

private struct LifetimeDaySnapshot {
    var day: DayKey
    var date: Date
    var totalUsage: TimeInterval
    var productivityScore: Int
    var controlScore: Int
    var detoxScore: Int
    var pauseSummary: PauseSuccessSummary
    var routineCompletions: Int
    var routineAttempts: Int
    var unproductiveUsage: TimeInterval
}

@MainActor
final class LifetimeViewModel: ObservableObject {
    private let usageDataService: UsageDataServicing
    private let pauseEventRepository: PauseEventRepository
    private let routineExecutionRepository: RoutineExecutionRepository
    private let appGroupStore: AppGroupStore
    private let productivityCalculator = WeightedProductivityScoreCalculator()
    private let controlCalculator = ControlScoreCalculator()
    private let detoxCalculator = DetoxScoreCalculator()
    private let bestDetoxCalculator = BestDetoxCalculator()
    private let baselineCalculator = BaselineCalculator()
    private let projectionCalculator = DigitalTimeProjectionCalculator()
    private let reclaimedTimeCalculator = ReclaimedTimeCalculator()
    private let routineAdherenceCalculator = RoutineAdherenceCalculator()

    @Published private(set) var state = LifetimeState()

    init(
        usageDataService: UsageDataServicing,
        pauseEventRepository: PauseEventRepository,
        routineExecutionRepository: RoutineExecutionRepository,
        appGroupStore: AppGroupStore
    ) {
        self.usageDataService = usageDataService
        self.pauseEventRepository = pauseEventRepository
        self.routineExecutionRepository = routineExecutionRepository
        self.appGroupStore = appGroupStore
    }

    func load() async {
        state.loadingState = .loading

        let snapshots = appGroupStore.loadAllScreenTimeReportSnapshots()
        guard !snapshots.isEmpty else {
            state = LifetimeState(
                loadingState: .insufficient("No Screen Time history has been written yet."),
                reclaimedTime: "--",
                baselineText: "Open Lockty on multiple days to build a baseline.",
                currentPace: "--",
                annualEquivalent: "--",
                trends: [],
                patterns: []
            )
            return
        }

        let pauseEvents = await pauseEventRepository.events(from: nil, to: nil)
        let routineExecutions = (try? await routineExecutionRepository.executions(from: nil, to: nil)) ?? []

        var daySnapshots: [LifetimeDaySnapshot] = []
        for snapshot in snapshots {
            let dayStart = date(for: snapshot.day)
            let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(24 * 60 * 60)

            guard let usageSummary = try? await usageDataService.usageSummary(for: dayStart) else {
                continue
            }

            let dayRange = dayStart..<dayEnd
            let dayPauseEvents = pauseEvents.filter { dayRange.contains($0.triggeredAt) }
            let dayRoutineExecutions = routineExecutions.filter { dayRange.contains($0.startedAt) }

            let unproductiveUsage = usageSummary.applications
                .filter { $0.classification == .unproductive }
                .reduce(0) { $0 + $1.duration }

            let pauseSummary = PauseSuccessCalculator().summary(from: dayPauseEvents)
            let completedRoutines = dayRoutineExecutions.filter { $0.endedAt != nil }.count
            let routineAttempts = dayRoutineExecutions.count
            let fragmentedPenalty = max(0, snapshot.activitySegments.count - 16)
            let classifiedUsages = usageSummary.applications.map {
                ClassifiedUsageDuration(
                    duration: $0.duration,
                    classification: $0.classification
                )
            }

            let productivity = productivityCalculator.score(
                for: classifiedUsages
            )

            let routineCompletionRate: Double
            if routineAttempts > 0 {
                routineCompletionRate = Double(completedRoutines) / Double(routineAttempts)
            } else {
                routineCompletionRate = 0
            }

            let restrictionAdherenceRate: Double
            if pauseSummary.triggeredCount > 0 {
                restrictionAdherenceRate = Double(pauseSummary.stoppedCount) / Double(pauseSummary.triggeredCount)
            } else {
                restrictionAdherenceRate = routineCompletionRate
            }

            let control = controlCalculator.score(
                from: ControlScoreInput(
                    routineCompletionRate: routineCompletionRate,
                    pauseAbandonmentRate: pauseSummary.successRate ?? 0,
                    restrictionAdherenceRate: restrictionAdherenceRate,
                    fragmentedUsagePenalty: Double(fragmentedPenalty)
                )
            )

            let usageIntervals = snapshot.activitySegments.map(\.dateInterval).map {
                UsageActivityInterval(start: $0.start, end: $0.end)
            }
            let bestDetoxResult = bestDetoxCalculator.longestInactivePeriod(
                usageIntervals: usageIntervals,
                dayStart: dayStart,
                dayEnd: dayEnd
            )
            let meaningfulDetox = meaningfulDetoxDuration(
                from: snapshot.activitySegments,
                dayStart: dayStart,
                dayEnd: dayEnd
            )
            let detox = detoxCalculator.score(
                from: DetoxScoreInput(
                    longestPhoneFreeInterval: bestDetoxResult.duration ?? 0,
                    meaningfulPhoneFreeTime: meaningfulDetox,
                    interruptionCount: snapshot.activitySegments.count
                )
            )

            daySnapshots.append(
                LifetimeDaySnapshot(
                    day: snapshot.day,
                    date: dayStart,
                    totalUsage: usageSummary.totalUsage,
                    productivityScore: productivity.roundedValue ?? 0,
                    controlScore: control.roundedValue,
                    detoxScore: detox.roundedValue,
                    pauseSummary: pauseSummary,
                    routineCompletions: completedRoutines,
                    routineAttempts: routineAttempts,
                    unproductiveUsage: unproductiveUsage
                )
            )
        }

        let uniqueDays = deduplicatedSnapshots(from: daySnapshots)
        guard !uniqueDays.isEmpty else {
            state = LifetimeState(
                loadingState: .insufficient("Lockty has no readable day summaries yet."),
                reclaimedTime: "--",
                baselineText: "Waiting for local history.",
                currentPace: "--",
                annualEquivalent: "--",
                trends: [],
                patterns: []
            )
            return
        }

        let baselineWindow = Array(uniqueDays.prefix(min(7, uniqueDays.count)))
        let currentWindow = Array(uniqueDays.suffix(min(7, uniqueDays.count)))
        guard let baseline = baselineCalculator.calculate(
            dailyUsages: uniqueDays.map(\.totalUsage),
            baselineWindow: min(7, uniqueDays.count),
            currentWindow: min(7, uniqueDays.count)
        ) else {
            state = LifetimeState(
                loadingState: .insufficient("Lockty could not derive a usage baseline yet."),
                reclaimedTime: "--",
                baselineText: "Waiting for enough local history.",
                currentPace: "--",
                annualEquivalent: "--",
                trends: [],
                patterns: []
            )
            return
        }

        let baselineDistractingUsage = baselineWindow.isEmpty
            ? 0
            : baselineWindow.reduce(0) { $0 + $1.unproductiveUsage } / Double(baselineWindow.count)
        let reclaimedTotal = reclaimedTimeCalculator.reclaimedTime(
            from: ReclaimedTimeInput(
                baselineDistractingUsagePerDay: baselineDistractingUsage,
                measuredDistractingUsageByDay: uniqueDays.map(\.unproductiveUsage)
            )
        )
        let projection = projectionCalculator.project(
            averageDailyUsage: baseline.currentAverageDailyUsage,
            horizon: 365 * 24 * 60 * 60
        )

        state = LifetimeState(
            loadingState: uniqueDays.count >= 3 ? .loaded : .insufficient("More tracked days are needed before Lockty can show reliable lifetime trends."),
            reclaimedTime: LocktyDurationFormatter.abbreviated(reclaimedTotal),
            baselineText: baselineText(totalDays: uniqueDays.count, baseline: baseline),
            currentPace: "\(LocktyDurationFormatter.abbreviated(projection.averageDailyUsage)) / day",
            annualEquivalent: "\(Int(projection.equivalentFullDaysPerYear.rounded())) days / year",
            trends: makeTrends(current: currentWindow, baseline: baselineWindow),
            patterns: makePatterns(days: uniqueDays, pauseEvents: pauseEvents)
        )
    }

    private func deduplicatedSnapshots(from snapshots: [LifetimeDaySnapshot]) -> [LifetimeDaySnapshot] {
        Dictionary(uniqueKeysWithValues: snapshots.map { ($0.day.id, $0) })
            .values
            .sorted { $0.date < $1.date }
    }

    private func date(for day: DayKey) -> Date {
        var calendar = Calendar(identifier: day.calendarIdentifier)
        calendar.timeZone = TimeZone(identifier: day.timeZoneIdentifier) ?? .current

        let components = DateComponents(year: day.year, month: day.month, day: day.day)
        return calendar.date(from: components) ?? .distantPast
    }

    private func meaningfulDetoxDuration(
        from segments: [ScreenTimeActivitySegmentSnapshot],
        dayStart: Date,
        dayEnd: Date
    ) -> TimeInterval {
        let intervals = segments
            .map(\.dateInterval)
            .sorted { $0.start < $1.start }

        guard !intervals.isEmpty else {
            return dayEnd.timeIntervalSince(dayStart)
        }

        var cursor = dayStart
        var total: TimeInterval = 0

        for interval in intervals {
            let gap = interval.start.timeIntervalSince(cursor)
            if gap >= 15 * 60 {
                total += gap
            }
            cursor = max(cursor, interval.end)
        }

        let finalGap = dayEnd.timeIntervalSince(cursor)
        if finalGap >= 15 * 60 {
            total += finalGap
        }

        return total
    }

    private func averageScore(
        _ keyPath: KeyPath<LifetimeDaySnapshot, Int>,
        for snapshots: [LifetimeDaySnapshot]
    ) -> Double {
        guard !snapshots.isEmpty else { return 0 }
        let total = snapshots.reduce(0) { $0 + Double($1[keyPath: keyPath]) }
        return total / Double(snapshots.count)
    }

    private func averagePauseSuccess(for snapshots: [LifetimeDaySnapshot]) -> Double {
        let summaries = snapshots.map(\.pauseSummary)
        let decisions = summaries.reduce(0) { $0 + $1.decisionCount }
        guard decisions > 0 else { return 0 }
        let stopped = summaries.reduce(0) { $0 + $1.stoppedCount }
        return Double(stopped) / Double(decisions)
    }

    private func baselineText(totalDays: Int, baseline: UsageBaseline) -> String {
        guard totalDays >= 3 else {
            return "Lockty needs more days before baseline comparisons become reliable."
        }

        let delta = baseline.deltaPerDay
        let direction = delta >= 0 ? "less" : "more"
        return "Compared with your earliest tracked days, you're using \(LocktyDurationFormatter.abbreviated(abs(delta))) \(direction) per day."
    }

    private func makeTrends(
        current: [LifetimeDaySnapshot],
        baseline: [LifetimeDaySnapshot]
    ) -> [LifetimeTrend] {
        let currentProductivity = averageScore(\.productivityScore, for: current)
        let baselineProductivity = averageScore(\.productivityScore, for: baseline)
        let currentControl = averageScore(\.controlScore, for: current)
        let baselineControl = averageScore(\.controlScore, for: baseline)
        let currentDetox = averageScore(\.detoxScore, for: current)
        let baselineDetox = averageScore(\.detoxScore, for: baseline)
        let currentPauseSuccess = averagePauseSuccess(for: current)
        let baselinePauseSuccess = averagePauseSuccess(for: baseline)
        let currentCompletedTasks = current.reduce(0) { $0 + $1.routineCompletions }
        let currentAttemptedRoutines = current.reduce(0) { $0 + $1.routineAttempts }
        let baselineCompletedTasks = baseline.reduce(0) { $0 + $1.routineCompletions }
        let baselineAttemptedRoutines = baseline.reduce(0) { $0 + $1.routineAttempts }
        let currentAdherence = routineAdherenceCalculator.calculate(
            from: RoutineAdherenceInput(
                completedExecutions: currentAttemptedRoutines > 0 ? currentAttemptedRoutines : 0,
                attemptedExecutions: currentAttemptedRoutines,
                completedTasks: currentCompletedTasks,
                totalTasks: max(currentCompletedTasks, currentAttemptedRoutines)
            )
        )
        let baselineAdherence = routineAdherenceCalculator.calculate(
            from: RoutineAdherenceInput(
                completedExecutions: baselineAttemptedRoutines > 0 ? baselineAttemptedRoutines : 0,
                attemptedExecutions: baselineAttemptedRoutines,
                completedTasks: baselineCompletedTasks,
                totalTasks: max(baselineCompletedTasks, baselineAttemptedRoutines)
            )
        )

        return [
            LifetimeTrend(
                id: "productivity",
                title: "Productivity",
                value: "\(Int(currentProductivity.rounded()))%",
                detail: deltaText(currentProductivity - baselineProductivity, suffix: "pts vs baseline")
            ),
            LifetimeTrend(
                id: "control",
                title: "Control",
                value: "\(Int(currentControl.rounded()))%",
                detail: deltaText(currentControl - baselineControl, suffix: "pts vs baseline")
            ),
            LifetimeTrend(
                id: "detox",
                title: "Detox",
                value: "\(Int(currentDetox.rounded()))%",
                detail: deltaText(currentDetox - baselineDetox, suffix: "pts vs baseline")
            ),
            LifetimeTrend(
                id: "pause-success",
                title: "Pause Success",
                value: "\(Int((currentPauseSuccess * 100).rounded()))%",
                detail: deltaText((currentPauseSuccess - baselinePauseSuccess) * 100, suffix: "pts vs baseline")
            ),
            LifetimeTrend(
                id: "routine-adherence",
                title: "Routine Adherence",
                value: "\(Int((currentAdherence.combinedRate * 100).rounded()))%",
                detail: deltaText((currentAdherence.combinedRate - baselineAdherence.combinedRate) * 100, suffix: "pts vs baseline")
            )
        ]
    }

    private func makePatterns(days: [LifetimeDaySnapshot], pauseEvents: [PauseEvent]) -> [String] {
        var patterns: [String] = []

        if let strongestDay = days.max(by: { $0.productivityScore < $1.productivityScore }) {
            patterns.append("Your strongest Productivity day reached \(strongestDay.productivityScore)% on \(strongestDay.date.formatted(date: .abbreviated, time: .omitted)).")
        }

        let lateNightEvents = pauseEvents.filter {
            let hour = Calendar.current.component(.hour, from: $0.triggeredAt)
            return hour >= 22 || hour < 1
        }
        if !lateNightEvents.isEmpty {
            patterns.append("Most Pause pressure is happening late at night, with \(lateNightEvents.count) events after 22:00.")
        }

        let routineDays = days.filter { $0.routineAttempts > 0 }
        if !routineDays.isEmpty {
            let completionRate = Double(routineDays.reduce(0) { $0 + $1.routineCompletions }) / Double(max(routineDays.reduce(0) { $0 + $1.routineAttempts }, 1))
            patterns.append("Routine adherence is \(Int((completionRate * 100).rounded()))% across tracked routine days.")
        }

        if patterns.isEmpty {
            patterns.append("Lockty is still collecting enough history to identify repeatable patterns.")
        }

        return patterns
    }

    private func deltaText(_ delta: Double, suffix: String) -> String {
        let rounded = Int(delta.rounded())
        if rounded == 0 {
            return "No change vs baseline"
        }
        let prefix = rounded > 0 ? "+" : ""
        return "\(prefix)\(rounded) \(suffix)"
    }
}
