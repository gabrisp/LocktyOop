import Foundation

nonisolated struct PauseRuleSnapshot: Codable, Hashable, Identifiable {
    var id: UUID
    var application: AppIdentity
    var isEnabled: Bool
    var steps: [PauseStep]
    var allowanceDuration: TimeInterval
    var relockAfterAllowance: Bool
    var updatedAt: Date

    init(rule: PauseRule) {
        id = rule.id
        application = rule.application
        isEnabled = rule.isEnabled
        steps = rule.steps
        allowanceDuration = rule.allowanceDuration
        relockAfterAllowance = rule.relockAfterAllowance
        updatedAt = rule.updatedAt
    }
}
