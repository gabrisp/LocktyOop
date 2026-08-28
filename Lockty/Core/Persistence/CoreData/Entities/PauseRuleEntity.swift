import CoreData
import Foundation

@objc(PauseRuleEntity)
final class PauseRuleEntity: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var appID: String
    @NSManaged var appDisplayName: String
    @NSManaged var appBundleIdentifier: String?
    @NSManaged var appIconSystemName: String?
    @NSManaged var appIconArtworkURL: String?
    @NSManaged var appTokenData: Data?
    @NSManaged var familyActivitySelectionData: Data?
    @NSManaged var isEnabled: Bool
    @NSManaged var allowanceDuration: Double
    @NSManaged var relockAfterAllowance: Bool
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date

    @NSManaged var steps: Set<PauseStepEntity>
    @NSManaged var events: Set<PauseEventEntity>
}

extension PauseRuleEntity {
    @nonobjc class func fetchRequest() -> NSFetchRequest<PauseRuleEntity> {
        NSFetchRequest<PauseRuleEntity>(entityName: "PauseRule")
    }
}
