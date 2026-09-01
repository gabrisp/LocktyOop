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

/// Derived, and derived off the main actor.
///
/// These are read by the shield action and monitor extensions, which have no main actor
/// to hop to. The type is declared `nonisolated`, but an extension in a module that
/// defaults to main-actor isolation does not inherit that, so each of these says so.
extension ScreenTimeSelectionRecord {
    nonisolated var blockedApplications: Set<AppIdentity.ID> {
        Set(selection.applicationTokens.map(AppIdentity.ID.init(token:)))
    }

    nonisolated var blockedDomains: Set<String> {
        Set(selection.webDomainTokens.compactMap { ManagedSettings.WebDomain(token: $0).domain })
    }

    nonisolated var applications: [AppIdentity] {
        selection.applicationTokens
            .map(AppIdentity.init(token:))
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    nonisolated func isContained(in policy: ShieldPolicy) -> Bool {
        let hasAnySelection = !selection.applicationTokens.isEmpty
            || !selection.categoryTokens.isEmpty
            || !selection.webDomainTokens.isEmpty
        guard hasAnySelection else { return false }

        // A record that resolves to no application ids at all is not "covered by every
        // policy" -- the empty set is a subset of anything, so without this a record
        // whose ids could not be derived was merged into every shield.
        guard !blockedApplications.isEmpty || !selection.applicationTokens.isEmpty else {
            return false
        }
        if !selection.applicationTokens.isEmpty && blockedApplications.isEmpty {
            return false
        }

        // Exempt apps count as covered: a pause allowance removes the released app from
        // blockedApplications, and without this the routine record that also contains
        // that app stopped being a subset, so the merge dropped the record whole and
        // unshielded every other app the routine blocks.
        return blockedApplications.isSubset(of: policy.blockedApplications.union(policy.exemptApplications))
            && blockedDomains.isSubset(of: policy.blockedDomains)
    }
}
