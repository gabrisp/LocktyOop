import CoreData
import Foundation

@objc(PauseStepEntity)
final class PauseStepEntity: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var kindRawValue: String
    @NSManaged var order: Int16
    @NSManaged var configData: Data

    @NSManaged var pauseRule: PauseRuleEntity?
}

extension PauseStepEntity {
    @nonobjc class func fetchRequest() -> NSFetchRequest<PauseStepEntity> {
        NSFetchRequest<PauseStepEntity>(entityName: "PauseStep")
    }
}
