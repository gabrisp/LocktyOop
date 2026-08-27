import Foundation

struct AppClassificationMapper {
    func apply(appID: AppIdentity.ID, classification: AppClassification, to entity: AppClassificationEntity) {
        entity.appID = appID.rawValue
        entity.displayName = appID.rawValue
        entity.classificationRawValue = classification.rawValue
        entity.updatedAt = Date()
    }

    func makeDomain(from entity: AppClassificationEntity) -> AppClassification? {
        AppClassification(rawValue: entity.classificationRawValue)
    }
}
