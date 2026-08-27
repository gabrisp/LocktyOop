import Foundation

struct ControlScoreInput: Codable, Hashable {
    var routineCompletionRate: Double
    var pauseAbandonmentRate: Double
    var restrictionAdherenceRate: Double
    var fragmentedUsagePenalty: Double
}

protocol ControlScoreCalculating {
    func score(from input: ControlScoreInput) -> DailyScoreResult
}

struct ControlScoreCalculator: ControlScoreCalculating {
    func score(from input: ControlScoreInput) -> DailyScoreResult {
        let routineComponent = clamped(input.routineCompletionRate) * 55
        let pauseComponent = clamped(input.pauseAbandonmentRate) * 20
        let restrictionComponent = clamped(input.restrictionAdherenceRate) * 25
        let rawScore = routineComponent + pauseComponent + restrictionComponent - max(input.fragmentedUsagePenalty, 0)

        return DailyScoreResult(rawValue: rawScore)
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
