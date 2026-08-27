import Foundation

struct DetoxScoreInput: Codable, Hashable {
    var longestPhoneFreeInterval: TimeInterval
    var meaningfulPhoneFreeTime: TimeInterval
    var interruptionCount: Int
}

protocol DetoxScoreCalculating {
    func score(from input: DetoxScoreInput) -> DailyScoreResult
}

struct DetoxScoreCalculator: DetoxScoreCalculating {
    private let longestTarget: TimeInterval = 3 * 60 * 60
    private let meaningfulTimeTarget: TimeInterval = 8 * 60 * 60
    private let interruptionLimit = 24

    func score(from input: DetoxScoreInput) -> DailyScoreResult {
        let longestComponent = min(max(input.longestPhoneFreeInterval, 0) / longestTarget, 1) * 45
        let totalComponent = min(max(input.meaningfulPhoneFreeTime, 0) / meaningfulTimeTarget, 1) * 40
        let interruptionComponent = max(
            0,
            1 - (Double(max(input.interruptionCount, 0)) / Double(interruptionLimit))
        ) * 15

        return DailyScoreResult(rawValue: longestComponent + totalComponent + interruptionComponent)
    }
}
