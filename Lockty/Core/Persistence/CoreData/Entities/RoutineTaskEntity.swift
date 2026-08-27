import CoreData
import Foundation

@objc(RoutineTaskEntity)
final class RoutineTaskEntity: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var title: String
    @NSManaged var icon: String?
    @NSManaged var order: Int16
    @NSManaged var isOptional: Bool

    @NSManaged var routine: RoutineEntity?
}

extension RoutineTaskEntity {
    @nonobjc class func fetchRequest() -> NSFetchRequest<RoutineTaskEntity> {
        NSFetchRequest<RoutineTaskEntity>(entityName: "RoutineTask")
    }
}
