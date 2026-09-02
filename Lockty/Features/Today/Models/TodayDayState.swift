import Foundation

enum TodayLoadingState: Equatable {
    case loading
    case loaded
    case unavailable(String)
}

struct TodayDayState: Equatable {
    var day: Date
    var loadingState: TodayLoadingState
    var rawDebugText: String
    var activeRoutineChecklist: ActiveRoutineChecklistState?
    var primaryMetrics: PrimaryMetricsState
    var perspective: DailyPerspective
    var perspectives: [DailyPerspective]
    var activities: [DigitalActivity]
    var metrics: TodayMetricsState
    var timeline: UsageTimelineChartState
    var hourlyActivity: HourlyActivityState
    var appUsages: [AppUsageState]

    static func loading(day: Date) -> TodayDayState {
        TodayDayState(
            day: day,
            loadingState: .loading,
            rawDebugText: "Preparing Today diagnostics...",
            activeRoutineChecklist: nil,
            primaryMetrics: .loading,
            perspective: .loading,
            perspectives: DailyPerspective.loadingStack,
            activities: [],
            metrics: .loading,
            timeline: .empty,
            hourlyActivity: .empty,
            appUsages: placeholderAppUsages
        )
    }

    /// Shape for the app list to hold while the real data is on its way.
    ///
    /// The screen stays mounted and gets redacted rather than swapped for a spinner, so
    /// nothing jumps into place when the load lands -- the values just fill in.
    static let placeholderAppUsages: [AppUsageState] = {
        let durations: [TimeInterval] = [68 * 60, 40 * 60, 23 * 60, 21 * 60, 16 * 60]

        return durations.enumerated().map { index, duration -> AppUsageState in
            let identity = AppIdentity(
                id: AppIdentity.ID(rawValue: "placeholder.\(index)"),
                displayName: "Placeholder App"
            )

            return AppUsageState(
                app: identity,
                durationText: LocktyDurationFormatter.abbreviated(duration),
                duration: duration,
                classification: .neutral,
                comparisonText: nil
            )
        }
    }()
}

struct TodayMetricsState: Codable, Hashable {
    var screenTime: ScreenTimeCardState
    var bestDetox: BestDetoxCardState
    var routines: RoutineSummaryCardState
    var distractions: DistractionsCardState
    var pauseSuccess: PauseSuccessDayCardState
    var intentionalTime: IntentionalTimeCardState

    static let loading = TodayMetricsState(
        screenTime: ScreenTimeCardState(durationText: "--", comparisonText: "Loading"),
        bestDetox: BestDetoxCardState(durationText: "--", comparisonText: "Loading"),
        routines: RoutineSummaryCardState(valueText: "--", detailText: "Loading"),
        distractions: DistractionsCardState(valueText: "--", comparisonText: "Loading"),
        pauseSuccess: PauseSuccessDayCardState(valueText: "--", detailText: "Loading"),
        intentionalTime: IntentionalTimeCardState(valueText: "--", detailText: "Loading")
    )
}

enum TodayMetricKind { case screenTime, bestDetox, routines, pauseSuccess, distractions, intentionalTime }

struct PauseSuccessDayCardState: Codable, Hashable {
    var valueText: String
    var detailText: String
}

struct IntentionalTimeCardState: Codable, Hashable {
    var valueText: String
    var detailText: String
}

struct ScreenTimeCardState: Codable, Hashable {
    var durationText: String
    var comparisonText: String
}

struct BestDetoxCardState: Codable, Hashable {
    var durationText: String
    var comparisonText: String
}

struct RoutineSummaryCardState: Codable, Hashable {
    var valueText: String
    var detailText: String
}

struct DistractionsCardState: Codable, Hashable {
    var valueText: String
    var comparisonText: String
}

struct AppUsageState: Codable, Hashable, Identifiable {
    var id: AppIdentity.ID { app.id }

    var app: AppIdentity
    var durationText: String
    var duration: TimeInterval
    var classification: AppClassification
    var comparisonText: String?
    /// How many times it was opened and how many times it interrupted, both for this day.
    ///
    /// Carried alongside the duration because "two hours" and "two hours across forty
    /// openings" are different days, and the second one is the one worth saying out loud.
    var opens: Int
    var notifications: Int

    init(
        app: AppIdentity,
        durationText: String,
        duration: TimeInterval,
        classification: AppClassification,
        comparisonText: String? = nil,
        opens: Int = 0,
        notifications: Int = 0
    ) {
        self.app = app
        self.durationText = durationText
        self.duration = duration
        self.classification = classification
        self.comparisonText = comparisonText
        self.opens = opens
        self.notifications = notifications
    }
}

struct ActiveRoutineChecklistState: Equatable, Identifiable {
    let id: UUID
    var routineID: UUID
    var title: String
    var subtitle: String
    var completedCount: Int
    var totalCount: Int
    var items: [ActiveRoutineChecklistItemState]
}

struct ActiveRoutineChecklistItemState: Equatable, Identifiable {
    let id: UUID
    var title: String
    var isCompleted: Bool
    var completedAtText: String?
}
