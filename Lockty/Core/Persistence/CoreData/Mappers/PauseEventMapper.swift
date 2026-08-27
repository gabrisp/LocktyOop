import CoreData
import Foundation

struct PauseEventMapper {
    func apply(_ event: PauseEvent, to entity: PauseEventEntity) {
        entity.id = event.id
        entity.pauseRuleID = event.pauseRuleID
        entity.appID = event.application.id.rawValue
        entity.appDisplayName = event.application.displayName
        entity.triggeredAt = event.triggeredAt
        entity.completedAt = event.completedAt
        entity.intention = event.intention
        entity.decisionRawValue = event.decision.rawValue
        entity.allowanceDuration = event.allowanceDuration.map { NSNumber(value: $0) }
        entity.actualUsageDuration = event.actualUsageDuration.map { NSNumber(value: $0) }
    }

    func makeDomain(from entity: PauseEventEntity) -> PauseEvent? {
        guard let decision = PauseDecision(rawValue: entity.decisionRawValue) else { return nil }
        let application = AppIdentity(id: AppIdentity.ID(rawValue: entity.appID), displayName: entity.appDisplayName)
        return PauseEvent(
            id: entity.id,
            pauseRuleID: entity.pauseRuleID,
            application: application,
            triggeredAt: entity.triggeredAt,
            completedAt: entity.completedAt,
            intention: entity.intention,
            decision: decision,
            allowanceDuration: entity.allowanceDuration?.doubleValue,
            actualUsageDuration: entity.actualUsageDuration?.doubleValue
        )
    }
}
