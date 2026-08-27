import CoreData
import Foundation

@objc(RoutineTriggerEntity)
final class RoutineTriggerEntity: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var kindRawValue: String
    @NSManaged var configData: Data?

    @NSManaged var routine: RoutineEntity?
}

extension RoutineTriggerEntity {
    @nonobjc class func fetchRequest() -> NSFetchRequest<RoutineTriggerEntity> {
        NSFetchRequest<RoutineTriggerEntity>(entityName: "RoutineTrigger")
    }
}
