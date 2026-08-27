import CoreData
import Foundation

@objc(RoutineEntity)
final class RoutineEntity: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var icon: String?
    @NSManaged var colorHex: String?
    @NSManaged var modeRawValue: String
    @NSManaged var allowsPauseDuringStrictMode: Bool
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
    @NSManaged var blockedApplicationIDsData: Data
    @NSManaged var blockedDomainsData: Data
    @NSManaged var breakPolicyData: Data
    @NSManaged var familyActivitySelectionData: Data?

    @NSManaged var tasks: Set<RoutineTaskEntity>
    @NSManaged var triggers: Set<RoutineTriggerEntity>
    @NSManaged var executions: Set<RoutineExecutionEntity>
}

extension RoutineEntity {
    @nonobjc class func fetchRequest() -> NSFetchRequest<RoutineEntity> {
        NSFetchRequest<RoutineEntity>(entityName: "Routine")
    }
}
