import Foundation

enum TodayLoadingState: Equatable {
    case loading
    case loaded
    case unavailable(String)
}

struct TodayDayState: Equatable {
    var day: Date
    var loadingState: TodayLoadingState
    var primaryMetrics: PrimaryMetricsState
    var perspective: DailyPerspective
    var activities: [DigitalActivity]
    var metrics: TodayMetricsState
    var timeline: UsageTimelineChartState
    var appUsages: [AppUsageState]
    var patterns: [BehaviorPattern]

    static func loading(day: Date) -> TodayDayState {
        TodayDayState(
            day: day,
            loadingState: .loading,
            primaryMetrics: .loading,
            perspective: .loading,
            activities: [],
            metrics: .loading,
            timeline: .empty,
            appUsages: [],
            patterns: []
        )
    }
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
}
