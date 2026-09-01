import Foundation

nonisolated enum ScreenTimeSelectionScope: Codable, Hashable, Identifiable {
    case library
    case routine(UUID)
    case rule(UUID)
    case pause(UUID)
    case appGroup(UUID)
    case distracting

    var id: String {
        switch self {
        case .library:
            "library"
        case .routine(let id):
            "routine-\(id.uuidString)"
        case .rule(let id):
            "rule-\(id.uuidString)"
        case .pause(let id):
            "pause-\(id.uuidString)"
        case .appGroup(let id):
            "app-group-\(id.uuidString)"
        case .distracting:
            "distracting"
        }
    }

    nonisolated static func appGroupScope(for appGroupID: UUID) -> ScreenTimeSelectionScope {
        ReusableAppGroupDefinition.selectionScope(for: appGroupID) ?? .appGroup(appGroupID)
    }
}
