import Foundation
import FamilyControls
import ManagedSettings

nonisolated struct ScreenTimeSelectionRecord: Codable, Identifiable {
    var scope: ScreenTimeSelectionScope
    var selection: FamilyActivitySelection
    var updatedAt: Date

    var id: String { scope.id }

    init(
        scope: ScreenTimeSelectionScope,
        selection: FamilyActivitySelection,
        updatedAt: Date = Date()
    ) {
        self.scope = scope
        self.selection = selection
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case scope
        case selectionData
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scope = try container.decode(ScreenTimeSelectionScope.self, forKey: .scope)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        let selectionData = try container.decodeIfPresent(Data.self, forKey: .selectionData)
        selection = try FamilyActivitySelection.unarchive(from: selectionData) ?? FamilyActivitySelection()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(scope, forKey: .scope)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(selection.archivedData(), forKey: .selectionData)
    }
}

extension ScreenTimeSelectionRecord {
    var blockedApplications: Set<AppIdentity.ID> {
        Set(selection.applicationTokens.map(AppIdentity.ID.init(token:)))
    }

    var blockedDomains: Set<String> {
        Set(selection.webDomainTokens.compactMap { ManagedSettings.WebDomain(token: $0).domain })
    }

    var applications: [AppIdentity] {
        selection.applicationTokens
            .map(AppIdentity.init(token:))
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
}
