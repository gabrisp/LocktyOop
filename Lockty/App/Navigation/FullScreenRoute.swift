import Foundation

enum FullScreenRoute: Hashable, Identifiable {
    case pause(PauseContext)
    case activeRoutine(UUID)

    var id: String {
        switch self {
        case .pause(let context): "pause-\(context.id.uuidString)"
        case .activeRoutine(let id): "active-routine-\(id.uuidString)"
        }
    }
}
