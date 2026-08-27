import Foundation
import SwiftData
import FamilyControls

@Model
final class RoutineRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var icon: String?
    var modeRawValue: String
    var triggersData: Data
    var familyActivitySelectionData: Data?
    var blockedApplicationIDsData: Data
    var blockedDomainsData: Data
    var tasksData: Data
    var breakPolicyData: Data
    var allowsPauseDuringStrictMode: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        name: String,
        icon: String?,
        mode: RoutineMode,
        triggersData: Data,
        familyActivitySelectionData: Data?,
        blockedApplicationIDsData: Data,
        blockedDomainsData: Data,
        tasksData: Data,
        breakPolicyData: Data,
        allowsPauseDuringStrictMode: Bool,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        modeRawValue = mode.rawValue
        self.triggersData = triggersData
        self.familyActivitySelectionData = familyActivitySelectionData
        self.blockedApplicationIDsData = blockedApplicationIDsData
        self.blockedDomainsData = blockedDomainsData
        self.tasksData = tasksData
        self.breakPolicyData = breakPolicyData
        self.allowsPauseDuringStrictMode = allowsPauseDuringStrictMode
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
