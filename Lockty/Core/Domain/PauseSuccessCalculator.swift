import Foundation

struct PauseSuccessSummary: Codable, Hashable {
    var triggeredCount: Int
    var stoppedCount: Int
    var continuedCount: Int

    var decisionCount: Int {
        stoppedCount + continuedCount
    }

    var successRate: Double? {
        guard decisionCount > 0 else { return nil }
        return Double(stoppedCount) / Double(decisionCount)
    }

    var successRateValue: Int? {
        successRate.map { Int(($0 * 100).rounded()) }
    }
}

protocol PauseSuccessCalculating {
    func summary(from events: [PauseEvent]) -> PauseSuccessSummary
}

struct PauseSuccessCalculator: PauseSuccessCalculating {
    func summary(from events: [PauseEvent]) -> PauseSuccessSummary {
        PauseSuccessSummary(
            triggeredCount: events.count,
            stoppedCount: events.filter { $0.decision == .abandoned }.count,
            continuedCount: events.filter { $0.decision == .continued }.count
        )
    }
}
