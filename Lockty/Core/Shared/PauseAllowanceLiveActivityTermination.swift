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
    /// Waits for the end to land rather than firing it off. A monitor extension's
    /// callback returns and the process goes away with it, so the detached task this
    /// used to start was collected before ActivityKit had done anything -- the shields
    /// went back on at the right second and the countdown stayed on the Lock Screen.
    static func endAllBlocking(timeout: TimeInterval = 5) {
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            await endAll()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + timeout)
    }
}
