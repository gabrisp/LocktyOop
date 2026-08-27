import CoreData
import Foundation

@objc(RoutineExecutionEntity)
final class RoutineExecutionEntity: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var routineID: UUID
    @NSManaged var routineName: String
    @NSManaged var startedAt: Date
    @NSManaged var endedAt: Date?
    @NSManaged var completionReasonRawValue: String?

    @NSManaged var routine: RoutineEntity?
    @NSManaged var taskCompletions: Set<RoutineTaskCompletionEntity>
    @NSManaged var breakEvents: Set<RoutineBreakEventEntity>
}

extension RoutineExecutionEntity {
    @nonobjc class func fetchRequest() -> NSFetchRequest<RoutineExecutionEntity> {
        NSFetchRequest<RoutineExecutionEntity>(entityName: "RoutineExecution")
    }
}
