import Foundation

nonisolated enum ScreenTimeSelectionScope: Codable, Hashable, Identifiable {
    case library
    case routine(UUID)
    case pause(UUID)

    var id: String {
        switch self {
        case .library:
            "library"
        case .routine(let id):
            "routine-\(id.uuidString)"
        case .pause(let id):
            "pause-\(id.uuidString)"
        }
    }
}
