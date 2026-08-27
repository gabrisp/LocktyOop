import Foundation
import SwiftData

@Model
final class PauseRuleRecord {
    @Attribute(.unique) var id: UUID
    var appID: String
    var appDisplayName: String
    var appBundleIdentifier: String?
    var appTokenData: Data?
    var appIconSystemName: String?
    var appIconArtworkURL: String?
    var isEnabled: Bool
    var stepsData: Data
    var allowanceDuration: TimeInterval
    var relockAfterAllowance: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        application: AppIdentity,
        isEnabled: Bool,
        stepsData: Data,
        allowanceDuration: TimeInterval,
        relockAfterAllowance: Bool,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.appID = application.id.rawValue
        self.appDisplayName = application.displayName
        self.appBundleIdentifier = application.bundleIdentifier
        self.appTokenData = try? JSONEncoder().encode(application.applicationToken)
        self.appIconSystemName = application.iconSystemName
        self.appIconArtworkURL = application.iconSource.remoteURL?.absoluteString
        self.isEnabled = isEnabled
        self.stepsData = stepsData
        self.allowanceDuration = allowanceDuration
        self.relockAfterAllowance = relockAfterAllowance
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
