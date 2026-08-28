#if canImport(ActivityKit)
import ActivityKit
#endif
import Foundation

/// Shared between the app and the Live Activity widget. Must be compiled into both
/// targets, so it lives in Core/Shared alongside the other cross-target models.
nonisolated struct PauseAllowanceActivityAttributes: Codable, Hashable {
    /// Fixed for the lifetime of the activity.
    var appDisplayName: String
    var allowanceDuration: TimeInterval

    nonisolated struct ContentState: Codable, Hashable {
        /// The countdown is driven by this date rather than a ticking value: the widget
        /// renders it with a relative/timer style so the system updates it every second
        /// without the app pushing an update per tick.
        var expiresAt: Date
        var startedAt: Date
    }
}

#if canImport(ActivityKit)
extension PauseAllowanceActivityAttributes: ActivityAttributes {}
#endif
