import Foundation

struct ReclaimedTimeInput: Codable, Hashable {
    var baselineDistractingUsagePerDay: TimeInterval
    var measuredDistractingUsageByDay: [TimeInterval]
}

protocol ReclaimedTimeCalculating {
    func reclaimedTime(from input: ReclaimedTimeInput) -> TimeInterval
}

struct ReclaimedTimeCalculator: ReclaimedTimeCalculating {
    func reclaimedTime(from input: ReclaimedTimeInput) -> TimeInterval {
        input.measuredDistractingUsageByDay.reduce(0) { total, measuredUsage in
            total + max(0, input.baselineDistractingUsagePerDay - measuredUsage)
        }
    }
}
