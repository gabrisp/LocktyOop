import Foundation

struct IntentionalTimeInput: Codable, Hashable {
    var productiveUsage: TimeInterval
    var neutralUsage: TimeInterval
    var routineUsage: TimeInterval
    var successfulPauseCount: Int
}

protocol IntentionalTimeCalculating {
    func intentionalTime(from input: IntentionalTimeInput) -> TimeInterval
}

struct IntentionalTimeCalculator: IntentionalTimeCalculating {
    func intentionalTime(from input: IntentionalTimeInput) -> TimeInterval {
        let weightedUsage = input.productiveUsage + (input.neutralUsage * 0.5)
        let pauseCredit = TimeInterval(input.successfulPauseCount * 3 * 60)
        return max(0, weightedUsage + input.routineUsage + pauseCredit)
    }
}
