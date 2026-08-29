import Foundation
import ManagedSettings

enum FullScreenRoute: Hashable, Identifiable {
    case pause(PauseContext)
    case activeRoutine(UUID)
    /// Choosing what to unlock and for how long. Carries the app when the flow was
    /// started from one, so that step is already answered.
    case unlockFlow(ApplicationToken?)

    var id: String {
        switch self {
        case .pause(let context): "pause-\(context.id.uuidString)"
        case .activeRoutine(let id): "active-routine-\(id.uuidString)"
        case .unlockFlow(let token): "unlock-\(token.map { AppIdentity.ID(token: $0).rawValue } ?? "all")"
        }
    }
}
