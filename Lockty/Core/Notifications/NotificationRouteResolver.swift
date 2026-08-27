import Foundation

struct NotificationRouteResolver {
    func resolve(_ payload: NotificationPayload) -> PendingSystemEvent? {
        switch payload.type {
        case .pauseRequested:
            guard let pauseContext = payload.pauseContext else { return nil }
            return PendingSystemEvent(
                source: .notification,
                payload: .pauseRequested(pauseContext),
                idempotencyKey: payload.idempotencyKey
            )

        case .routineReminder, .alarmAction:
            guard let routineID = payload.routineID else { return nil }
            return PendingSystemEvent(
                source: .notification,
                payload: .routineStartRequested(routineID),
                idempotencyKey: payload.idempotencyKey
            )

        case .authorizationRecovery, .relockFailed:
            return PendingSystemEvent(
                source: .notification,
                payload: .settingsRequested,
                idempotencyKey: payload.idempotencyKey
            )

        case .routineStarted, .routineEnding, .breakEnding:
            return nil
        }
    }
}
