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
            let context = makeUnlockRequest(for: applicationToken)
            writePendingPause(context)

            // iOS 26.5 answers this itself: .openParentalControlsApp brings up the app
            // that owns the shield, which is the whole point of the button. Everything
            // below it -- the runtime openURL: attempt, the notification held open until
            // it registered -- was working around the absence of exactly this.
            //
            // The request is already in the App Group, so Lockty finds it on foreground
            // without needing the deep link to carry it.
            if #available(iOS 26.5, *) {
                completionHandler(.openParentalControlsApp)
                return
            }

            // Older systems: ask through UIApplication and post the notification, which
            // is the only guaranteed way back since nothing reports whether the open
            // landed. Lockty pulls the notification the moment it picks the request up,
            // so a successful open leaves nothing stale behind.
            openLockty(for: context)

            // .defer, never .close. Closing is what the secondary button is for; the
            // primary must never be the thing that shuts the app the user just opened.
            //
            // Held until the notification is registered. Answering straight away let the
            // system tear this process down while the request was still being added, and
            // nothing was ever delivered.
            let responder = SingleResponse(completionHandler)
            postUnlockNotification(context) { responder.send(.defer) }
            // Nothing guarantees that callback arrives, and a shield left waiting on it
            // is worse than one that answers without its notification.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { responder.send(.defer) }

        case .secondaryButtonPressed:
            completionHandler(.close)

        default:
            completionHandler(.close)
        }
    }

    /// Builds the request from the running routine's own pause policy.
    ///
    /// Always returns one. It used to return nil when there was no active routine or the
    /// routine had no pause configured, and the caller answered .close on nil -- so the
    /// primary button's only visible effect was shutting the app. The standard flow
    /// stands in for every case it cannot read a policy for.
    private func makeUnlockRequest(for token: ApplicationToken) -> PauseContext {
        let runtime = try? appGroupStore.loadRuntimeState()
        let activeRoutine = runtime?.activeRoutine
        let policy = activeRoutine
            .map(\.pausePolicySnapshot)
            .flatMap { $0.offersPause ? $0 : nil }
            ?? .standard

        let application = Application(token: token)
        let identity = AppIdentity(token: token)

        return PauseContext(
            pauseRuleID: activeRoutine?.routineID ?? identity.id.rawValue.stableUUID,
            appID: identity.id,
            applicationToken: token,
            displayName: application.localizedDisplayName ?? identity.displayName,
            allowanceDuration: policy.allowanceDuration,
            steps: policy.steps,
            activeRoutineID: activeRoutine?.routineID,
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
        else {
            print("Shield action could not reach UIApplication to open Lockty")
            return
        }

        // Both are attempted, and neither is trusted. The old single-argument openURL:
        // is the one that has historically gone through from an extension, but it
        // returns nothing either way, so there is no way to tell whether it landed --
        // which is why the notification always goes out alongside this. It used to stop
        // after the legacy attempt, so on a system where that one is inert the modern
        // selector was never even tried.
        let legacySelector = NSSelectorFromString("openURL:")
        if application.responds(to: legacySelector) {
            application.perform(legacySelector, with: url)
            print("Shield action asked to open Lockty through openURL:")
        }

        let modernSelector = NSSelectorFromString("openURL:options:completionHandler:")
        guard application.responds(to: modernSelector) else { return }

        typealias OpenURL = @convention(c) (NSObject, Selector, NSURL, NSDictionary, Any?) -> Void
        let implementation = application.method(for: modernSelector)
        let open = unsafeBitCast(implementation, to: OpenURL.self)
        open(application, modernSelector, url as NSURL, NSDictionary(), nil)
        print("Shield action asked to open Lockty through openURL:options:completionHandler:")
    }

    private func postUnlockNotification(_ context: PauseContext, completion: @escaping () -> Void) {
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
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("Unlock notification could not be scheduled: \(error.localizedDescription)")
            }
            completion()
        }
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


/// Answers the shield exactly once, from whichever of the two paths gets there first.
private final class SingleResponse {
    private let completionHandler: (ShieldActionResponse) -> Void
    private let lock = NSLock()
    private var hasResponded = false

    init(_ completionHandler: @escaping (ShieldActionResponse) -> Void) {
        self.completionHandler = completionHandler
    }

    func send(_ response: ShieldActionResponse) {
        lock.lock()
        let shouldSend = !hasResponded
        hasResponded = true
        lock.unlock()
        guard shouldSend else { return }
        completionHandler(response)
    }
}
