import Foundation

enum SystemRouteCommand: Hashable {
    case selectTab(AppTab)
    case push(AppRoute)
    case sheet(SheetRoute)
    case fullScreen(FullScreenRoute)
    case startRoutine(UUID)
    case none
}

struct SystemEventRouter {
    func resolve(_ event: PendingSystemEvent) -> SystemRouteCommand {
        guard !event.isExpired else {
            return .none
        }

        switch event.payload {
        case .pauseRequested(let context):
            return .fullScreen(.unlockFlow(context.applicationToken))

        case .routineStartRequested(let routineID):
            return .startRoutine(routineID)

        case .settingsRequested:
            return .push(.settings)
        }
    }
}
