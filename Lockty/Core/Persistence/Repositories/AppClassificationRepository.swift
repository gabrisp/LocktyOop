import Foundation

protocol AppClassificationRepository {
    func classification(for appID: AppIdentity.ID) async -> AppClassification?
    func allClassifications() async -> [AppIdentity.ID: AppClassification]
    func saveClassification(_ classification: AppClassification, for appID: AppIdentity.ID) async
}
