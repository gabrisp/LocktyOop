import Foundation

nonisolated struct DigitalTimeProjection: Equatable {
    var averageDailyUsage: TimeInterval
    var weeklyUsage: TimeInterval
    var yearlyUsage: TimeInterval
    var equivalentFullDaysPerYear: Double
    var horizon: TimeInterval?
    var projectedUsageOverHorizon: TimeInterval?
    var equivalentFullDaysOverHorizon: Double?
    var equivalentFullYearsOverHorizon: Double?
    var provenance: MetricProvenance
}
