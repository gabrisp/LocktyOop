import Foundation
import ManagedSettings

struct UnlockFlowRoute: Hashable, Identifiable {
    let id: UUID
    var token: ApplicationToken?
    var context: PauseContext?

    init(token: ApplicationToken?) {
        self.id = token.map { AppIdentity.ID(token: $0).rawValue.stableUUID } ?? UUID()
        self.token = token
        self.context = nil
    }

    init(context: PauseContext) {
        self.id = context.id
        self.token = context.applicationToken
        self.context = context
    }
}

enum FullScreenRoute: Hashable, Identifiable {
    case activeRoutine(UUID)
    /// Choosing what to unlock and for how long. Carries the app when the flow was
    /// started from one, so that step is already answered.
    case unlockFlow(UnlockFlowRoute)

    var id: String {
        switch self {
        case .activeRoutine(let id): "active-routine-\(id.uuidString)"
        case .unlockFlow(let route): "unlock-\(route.id.uuidString)"
        }
    }
}
