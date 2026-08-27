import CoreData
import Foundation

@objc(RoutineBreakEventEntity)
final class RoutineBreakEventEntity: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var startedAt: Date
    @NSManaged var endedAt: Date?
    @NSManaged var triggerRawValue: String

    @NSManaged var execution: RoutineExecutionEntity?
}

extension RoutineBreakEventEntity {
    @nonobjc class func fetchRequest() -> NSFetchRequest<RoutineBreakEventEntity> {
        NSFetchRequest<RoutineBreakEventEntity>(entityName: "RoutineBreakEvent")
    }
}
