import Foundation
import SwiftData

@Model
final class PauseEventRecord {
    @Attribute(.unique) var id: UUID
    var pauseRuleID: UUID
    var appID: String
    var appDisplayName: String
    var triggeredAt: Date
    var completedAt: Date?
    var intention: String?
    var decisionRawValue: String
    var allowanceDuration: TimeInterval?
    var actualUsageDuration: TimeInterval?

    init(
        id: UUID,
        pauseRuleID: UUID,
        application: AppIdentity,
        triggeredAt: Date,
        completedAt: Date?,
        intention: String?,
        decision: PauseDecision,
        allowanceDuration: TimeInterval?,
        actualUsageDuration: TimeInterval?
    ) {
        self.id = id
        self.pauseRuleID = pauseRuleID
        self.appID = application.id.rawValue
        self.appDisplayName = application.displayName
        self.triggeredAt = triggeredAt
        self.completedAt = completedAt
        self.intention = intention
        self.decisionRawValue = decision.rawValue
        self.allowanceDuration = allowanceDuration
        self.actualUsageDuration = actualUsageDuration
    }
}
