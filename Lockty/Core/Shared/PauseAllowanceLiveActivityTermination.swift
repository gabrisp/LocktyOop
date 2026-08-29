#if canImport(ActivityKit)
import ActivityKit
#endif
import Foundation

/// Ending the allowance's Live Activity, from wherever the allowance happens to end.
///
/// Shared rather than kept on the app's controller because the allowance does not always
/// run out with the app running: the monitor extension is what notices the granted
/// minutes have been spent, and the countdown it leaves on the Lock Screen has to go with
/// the shields it puts back.
nonisolated enum PauseAllowanceLiveActivityTermination {
    static func endAll() async {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return }
        for activity in Activity<PauseAllowanceActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        #endif
    }

    /// For the extension callbacks, which are synchronous and cannot await.
    ///
    /// Best effort: the process is short-lived and may be gone before this lands. The
    /// app's own foreground path ends the activity too, so a missed one is stale until
    /// the next launch rather than permanent.
    static func endAllDetached() {
        Task { await endAll() }
    }
}
