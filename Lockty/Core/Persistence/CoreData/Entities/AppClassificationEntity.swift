import CoreData
import Foundation

@objc(AppClassificationEntity)
final class AppClassificationEntity: NSManagedObject {
    @NSManaged var appID: String
    @NSManaged var displayName: String
    @NSManaged var classificationRawValue: String
    @NSManaged var updatedAt: Date
}

extension AppClassificationEntity {
    @nonobjc class func fetchRequest() -> NSFetchRequest<AppClassificationEntity> {
        NSFetchRequest<AppClassificationEntity>(entityName: "AppClassification")
    }
}
