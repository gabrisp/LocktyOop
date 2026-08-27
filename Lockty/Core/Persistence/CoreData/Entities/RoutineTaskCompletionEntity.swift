import CoreData
import Foundation

@objc(RoutineTaskCompletionEntity)
final class RoutineTaskCompletionEntity: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var taskID: UUID
    @NSManaged var titleSnapshot: String
    @NSManaged var orderSnapshot: Int16
    @NSManaged var completedAt: Date?

    @NSManaged var execution: RoutineExecutionEntity?
}

extension RoutineTaskCompletionEntity {
    @nonobjc class func fetchRequest() -> NSFetchRequest<RoutineTaskCompletionEntity> {
        NSFetchRequest<RoutineTaskCompletionEntity>(entityName: "RoutineTaskCompletion")
    }
}
