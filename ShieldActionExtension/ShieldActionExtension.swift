import Foundation
import ManagedSettings
import UserNotifications

final class ShieldActionExtension: ShieldActionDelegate {
    private let appGroupStore = AppGroupStore()

    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        handle(action: action, applicationToken: application, completionHandler: completionHandler)
    }

    override func handle(
        action: ShieldAction,
        for webDomain: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        completionHandler(.close)
    }

    override func handle(
        action: ShieldAction,
        for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        completionHandler(.close)
    }

    /// Primary asks Lockty to unlock, secondary closes the app.
    ///
    /// Neither one depends on a per-app rule any more: the pause belongs to whichever
    /// routine is running, so the same two buttons work for every app it blocks.
    private func handle(
        action: ShieldAction,
        applicationToken: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        switch action {
        case .primaryButtonPressed:
            guard let context = makeUnlockRequest(for: applicationToken) else {
                completionHandler(.close)
                return
            }

            writePendingPause(context)
            // A shield action extension can't bring the app forward itself, and
            // ActivityKit can't be started from an extension either. A local
            // notification is the one route that works: tapping it opens Lockty, where
            // the request written above is surfaced as a card.
            postUnlockNotification(context)
            completionHandler(.defer)

        case .secondaryButtonPressed:
            completionHandler(.close)

        default:
            completionHandler(.close)
        }
    }

    /// Builds the request from the running routine's own pause policy.
    private func makeUnlockRequest(for token: ApplicationToken) -> PauseContext? {
        guard let runtime = try? appGroupStore.loadRuntimeState(),
              let activeRoutine = runtime.activeRoutine,
              activeRoutine.pausePolicySnapshot.offersPause
        else { return nil }

        let policy = activeRoutine.pausePolicySnapshot
        let application = Application(token: token)
        let identity = AppIdentity(token: token)

        return PauseContext(
            pauseRuleID: activeRoutine.routineID,
            appID: identity.id,
            applicationToken: token,
            displayName: application.localizedDisplayName ?? identity.displayName,
            allowanceDuration: policy.allowanceDuration,
            steps: policy.steps,
            activeRoutineID: activeRoutine.routineID,
            source: .shieldAction
        )
    }

    private func postUnlockNotification(_ context: PauseContext) {
        let content = UNMutableNotificationContent()
        content.title = "Solicitud de desbloqueo"
        content.body = "Toca para decidir sobre \(context.displayName) en Lockty."
        content.sound = .default
        content.userInfo = ["pauseRuleID": context.pauseRuleID.uuidString]

        // nil trigger delivers as soon as the system allows, rather than on a timer.
        let request = UNNotificationRequest(
            identifier: "pause-request-\(context.pauseRuleID.uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func writePendingPause(_ context: PauseContext) {
        let pendingContext = PendingPauseContext(
            context: context,
            expiresAt: Date().addingTimeInterval(10 * 60),
            idempotencyKey: context.id.uuidString
        )
        let event = PendingSystemEvent(
            source: .shieldAction,
            payload: .pauseRequested(context),
            expiresAt: pendingContext.expiresAt,
            idempotencyKey: pendingContext.idempotencyKey
        )

        try? appGroupStore.updateRuntimeState { state in
            state.pendingPause = pendingContext
            state.pendingEvents.append(event)
        }
    }
}
