import Foundation

nonisolated struct UsageBaseline: Equatable {
    var baselineAverageDailyUsage: TimeInterval
    var currentAverageDailyUsage: TimeInterval
    var baselineWindowDayCount: Int
    var currentWindowDayCount: Int
    var deltaPerDay: TimeInterval
}
