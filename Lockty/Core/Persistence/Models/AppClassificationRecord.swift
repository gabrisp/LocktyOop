import Foundation
import SwiftData

@Model
final class AppClassificationRecord {
    @Attribute(.unique) var appID: String
    var displayName: String
    var classificationRawValue: String
    var updatedAt: Date

    init(
        appID: String,
        displayName: String,
        classification: AppClassification,
        updatedAt: Date = Date()
    ) {
        self.appID = appID
        self.displayName = displayName
        classificationRawValue = classification.rawValue
        self.updatedAt = updatedAt
    }
}
