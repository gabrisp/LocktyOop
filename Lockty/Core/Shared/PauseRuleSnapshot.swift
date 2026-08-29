import Foundation

nonisolated struct PauseRuleSnapshot: Codable, Hashable, Identifiable {
    var id: UUID
    var application: AppIdentity
    /// The rule's display name, already resolved (user label when set, otherwise the
    /// app's own). Extensions read this rather than re-deriving it from a token.
    var displayName: String = ""
    var isEnabled: Bool
    var steps: [PauseStep]
    var allowanceDuration: TimeInterval
    var relockAfterAllowance: Bool
    var updatedAt: Date

    init(rule: PauseRule) {
        id = rule.id
        application = rule.application
        displayName = rule.displayName
        isEnabled = rule.isEnabled
        steps = rule.steps
        allowanceDuration = rule.allowanceDuration
        relockAfterAllowance = rule.relockAfterAllowance
        updatedAt = rule.updatedAt
    }
}
