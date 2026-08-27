import Foundation

protocol DigitalTimeProjecting {
    func project(averageDailyUsage: TimeInterval, horizon: TimeInterval?) -> DigitalTimeProjection
}

struct DigitalTimeProjectionCalculator: DigitalTimeProjecting {
    private let daysPerWeek = 7.0
    private let daysPerYear = 365.0
    private let secondsPerDay = 24.0 * 60.0 * 60.0
    private let secondsPerYear = 365.0 * 24.0 * 60.0 * 60.0

    func project(averageDailyUsage: TimeInterval, horizon: TimeInterval? = nil) -> DigitalTimeProjection {
        let dailyUsage = max(averageDailyUsage, 0)
        let weeklyUsage = dailyUsage * daysPerWeek
        let yearlyUsage = dailyUsage * daysPerYear
        let equivalentFullDaysPerYear = yearlyUsage / secondsPerDay

        let projectedUsageOverHorizon = horizon.map { max($0, 0) / secondsPerDay * dailyUsage }
        let equivalentFullDaysOverHorizon = projectedUsageOverHorizon.map { $0 / secondsPerDay }
        let equivalentFullYearsOverHorizon = projectedUsageOverHorizon.map { $0 / secondsPerYear }

        return DigitalTimeProjection(
            averageDailyUsage: dailyUsage,
            weeklyUsage: weeklyUsage,
            yearlyUsage: yearlyUsage,
            equivalentFullDaysPerYear: equivalentFullDaysPerYear,
            horizon: horizon,
            projectedUsageOverHorizon: projectedUsageOverHorizon,
            equivalentFullDaysOverHorizon: equivalentFullDaysOverHorizon,
            equivalentFullYearsOverHorizon: equivalentFullYearsOverHorizon,
            provenance: .projected
        )
    }
}
