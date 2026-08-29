import Foundation

nonisolated struct ShieldPolicy: Codable, Hashable {
    var blockedApplications: Set<AppIdentity.ID>
    var blockedDomains: Set<String>
    var reason: ShieldReason
    var selectionScopes: Set<ScreenTimeSelectionScope>
    /// Apps a granted pause allowance has released.
    ///
    /// Dropping them from `blockedApplications` is not enough: the shield is driven by
    /// the stored FamilyActivitySelection for the policy's reason, and that selection
    /// still contains the released app's token (and may block it through a whole
    /// category). The shield service needs to know which app to subtract, and which
    /// token to pass as the category exception, so it travels with the policy.
    var exemptApplications: Set<AppIdentity.ID>

    init(
        blockedApplications: Set<AppIdentity.ID>,
        blockedDomains: Set<String>,
        reason: ShieldReason,
        selectionScopes: Set<ScreenTimeSelectionScope> = [],
        exemptApplications: Set<AppIdentity.ID> = []
    ) {
        self.blockedApplications = blockedApplications
        self.blockedDomains = blockedDomains
        self.reason = reason
        self.selectionScopes = selectionScopes
        self.exemptApplications = exemptApplications
    }

    // Written by hand so a runtime state persisted before exemptApplications existed
    // still decodes instead of throwing keyNotFound and wiping the shield.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        blockedApplications = try container.decode(Set<AppIdentity.ID>.self, forKey: .blockedApplications)
        blockedDomains = try container.decode(Set<String>.self, forKey: .blockedDomains)
        reason = try container.decode(ShieldReason.self, forKey: .reason)
        selectionScopes = try container.decodeIfPresent(Set<ScreenTimeSelectionScope>.self, forKey: .selectionScopes) ?? []
        exemptApplications = try container.decodeIfPresent(Set<AppIdentity.ID>.self, forKey: .exemptApplications) ?? []
    }

    /// Whether this policy shields anything at all.
    ///
    /// Not `self == .empty`: a policy that releases an app through a pause allowance
    /// carries that app in `exemptApplications`, so it is never equal to `.empty` even
    /// when it blocks nothing -- and comparing against `.empty` sent the last unlock
    /// down the apply path, where an empty selection throws and the shield stayed up.
    var blocksNothing: Bool {
        blockedApplications.isEmpty && blockedDomains.isEmpty
    }

    static let empty = ShieldPolicy(
        blockedApplications: [],
        blockedDomains: [],
        reason: .none
    )

    static func routine(_ routine: Routine) -> ShieldPolicy {
        ShieldPolicy(
            blockedApplications: routine.blockedApplications,
            blockedDomains: routine.blockedDomains,
            reason: .routine(routine.id),
            selectionScopes: [.routine(routine.id)]
        )
    }
}

nonisolated enum ShieldReason: Codable, Hashable {
    case none
    case routine(UUID)
    case pause(AppIdentity.ID)
    case combined
}
