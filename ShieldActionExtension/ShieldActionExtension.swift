import Foundation
import ManagedSettings
import UIKit
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

            // The open is attempted first so it has the foreground request in flight
            // before the response is given, and the notification always goes out
            // alongside it -- there is no way to observe whether the open landed, so it
            // is the guaranteed way back. Lockty pulls the notification the moment it
            // picks the request up, so a successful open leaves nothing stale behind.
            openLockty(for: context)
            postUnlockNotification(context)

            // .defer, never .close. Closing is what the secondary button is for; the
            // primary must never be the thing that shuts the app the user just opened.
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

    /// Opens `lockty://unlock?...`.
    ///
    /// UIApplication is not visible to an app extension at compile time, so it is reached
    /// through the runtime. Both selectors are tried: the modern one is the API, but the
    /// old single-argument `openURL:` is the one that still goes through from an
    /// extension, so it gets the first attempt.
    private func openLockty(for context: PauseContext) {
        guard let url = URL(string: "lockty://unlock?request=\(context.id.uuidString)") else {
            return
        }

        let sharedSelector = NSSelectorFromString("sharedApplication")
        guard let applicationClass = NSClassFromString("UIApplication") as? NSObject.Type,
              applicationClass.responds(to: sharedSelector),
              let application = applicationClass.perform(sharedSelector)?.takeUnretainedValue() as? NSObject
        else { return }

        let legacySelector = NSSelectorFromString("openURL:")
        if application.responds(to: legacySelector) {
            application.perform(legacySelector, with: url)
            return
        }

        let modernSelector = NSSelectorFromString("openURL:options:completionHandler:")
        guard application.responds(to: modernSelector) else { return }

        typealias OpenURL = @convention(c) (NSObject, Selector, NSURL, NSDictionary, Any?) -> Void
        let implementation = application.method(for: modernSelector)
        let open = unsafeBitCast(implementation, to: OpenURL.self)
        open(application, modernSelector, url as NSURL, NSDictionary(), nil)
    }

    private func postUnlockNotification(_ context: PauseContext) {
        let content = UNMutableNotificationContent()
        content.title = "Unlock \(context.displayName)?"
        content.body = "Tap to decide in Lockty."
        content.sound = .default
        content.userInfo = ["pauseRuleID": context.pauseRuleID.uuidString]
        // Time sensitive so it comes through immediately and survives a Focus mode --
        // this notification is the only way an extension can get the user back into
        // Lockty, so it must not be held back or batched. iOS ignores this until the
        // Time Sensitive Notifications capability is enabled on the target; the
        // provisioning profile does not carry it yet.
        content.interruptionLevel = .timeSensitive

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
