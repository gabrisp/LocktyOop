import Foundation

nonisolated struct ApplicationUsage: Codable, Hashable, Identifiable {
    var id: AppIdentity.ID { app.id }

    let app: AppIdentity
    var duration: TimeInterval
    var classification: AppClassification
}

nonisolated struct ClassifiedUsageDuration: Codable, Hashable {
    var duration: TimeInterval
    var classification: AppClassification
}
