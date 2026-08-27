import CoreData
import Foundation

@objc(PauseEventEntity)
final class PauseEventEntity: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var pauseRuleID: UUID
    @NSManaged var appID: String
    @NSManaged var appDisplayName: String
    @NSManaged var triggeredAt: Date
    @NSManaged var completedAt: Date?
    @NSManaged var intention: String?
    @NSManaged var decisionRawValue: String
    @NSManaged var allowanceDuration: NSNumber?
    @NSManaged var actualUsageDuration: NSNumber?

    @NSManaged var pauseRule: PauseRuleEntity?
}

extension PauseEventEntity {
    @nonobjc class func fetchRequest() -> NSFetchRequest<PauseEventEntity> {
        NSFetchRequest<PauseEventEntity>(entityName: "PauseEvent")
    }
}
