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
            allowanceDuration: allowance.context.allowanceDuration,
            symbolName: Self.symbolName(for: allowance.context)
        )
        let state = PauseAllowanceActivityAttributes.ContentState(
            expiresAt: allowance.expiresAt,
            startedAt: allowance.startedAt
        )

        do {
            // Stale at the moment the allowance runs out, not never.
            //
            // Nothing of ours runs on the wall clock in the background -- DeviceActivity
            // refuses any window under fifteen minutes, so a short allowance has no
            // background event at all -- and the activity used to sit there afterwards
            // reading 0:00 until Lockty was opened and `relock` ended it. A stale date is
            // the one thing the system will honour on its own: it dims the activity at
            // expiry and takes it away without anybody being there to ask.
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
        await PauseAllowanceLiveActivityTermination.endAll()
    }

    /// The face of whatever is holding the app, decided the same way the shield screen
    /// decides it: an hourglass for a limit, the routine's own glyph for a routine, a
    /// shield when there is neither.
    ///
    /// Read from the runtime state rather than carried on the context, because the icon
    /// belongs to the routine and the context is about the app.
    private static func symbolName(for context: PauseContext) -> String {
        guard context.limitRuleID == nil else { return "hourglass" }

        guard let routineID = context.activeRoutineID,
              let routine = (try? AppGroupStore().loadRuntimeState())?
                  .activeRoutines
                  .first(where: { $0.routineID == routineID }),
              let icon = routine.iconSnapshot,
              !icon.isEmpty
        else { return "shield.fill" }

        return icon
    }
}
