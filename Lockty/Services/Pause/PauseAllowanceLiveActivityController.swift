#if canImport(ActivityKit)
import ActivityKit
#endif
import Foundation
import OSLog

private let liveActivityLogger = Logger(subsystem: "com.gabrisp.Lockty", category: "liveActivity")

/// Shows the remaining allowance as a Live Activity while the user is in the app they
/// unlocked, so the countdown stays visible on the Lock Screen / Dynamic Island.
///
/// Requires a Widget Extension target hosting a `PauseAllowanceActivityAttributes`
/// widget; without one `Activity.request` throws and this quietly does nothing, which
/// is why every call site ignores failures rather than surfacing them.
protocol PauseAllowanceLiveActivityControlling: Sendable {
    func start(for allowance: ActivePauseAllowance) async
    func end() async
}

final class PauseAllowanceLiveActivityController: PauseAllowanceLiveActivityControlling {
    func start(for allowance: ActivePauseAllowance) async {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            liveActivityLogger.notice("Live Activities disabled by the user; skipping pause allowance activity")
            return
        }

        // Only ever one allowance runs at a time.
        await end()

        let attributes = PauseAllowanceActivityAttributes(
            appDisplayName: allowance.context.displayName,
            allowanceDuration: allowance.context.allowanceDuration
        )
        let state = PauseAllowanceActivityAttributes.ContentState(
            expiresAt: allowance.expiresAt,
            startedAt: allowance.startedAt
        )

        do {
            _ = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: allowance.expiresAt),
                pushType: nil
            )
            liveActivityLogger.notice("Started pause allowance Live Activity for \(allowance.context.displayName, privacy: .public)")
        } catch {
            liveActivityLogger.error("Could not start pause allowance Live Activity: \(error.localizedDescription, privacy: .public)")
        }
        #endif
    }

    func end() async {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return }
        for activity in Activity<PauseAllowanceActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        #endif
    }
}
