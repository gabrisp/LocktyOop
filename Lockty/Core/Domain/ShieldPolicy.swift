import Foundation

nonisolated struct ShieldPolicy: Codable, Hashable {
    var blockedApplications: Set<AppIdentity.ID>
    var blockedDomains: Set<String>
    var reason: ShieldReason

    static let empty = ShieldPolicy(
        blockedApplications: [],
        blockedDomains: [],
        reason: .none
    )

    static func routine(_ routine: Routine) -> ShieldPolicy {
        ShieldPolicy(
            blockedApplications: routine.blockedApplications,
            blockedDomains: routine.blockedDomains,
            reason: .routine(routine.id)
        )
    }
}

nonisolated enum ShieldReason: Codable, Hashable {
    case none
    case routine(UUID)
    case pause(AppIdentity.ID)
    case combined
}
