import Foundation

/// A debug-only stop that stays stopped.
///
/// Killing every block is easy; keeping it dead is the hard half. Half a dozen things in
/// this app put shields back on their own -- the schedule coordinator re-registers every
/// monitor when a list loads, the pause engine recomputes the policy after almost any
/// change, and the monitor extension repairs the runtime state whenever an interval turns
/// over. Without a latch, "kill everything" is a pause of a few seconds.
///
/// So the kill sets this, and the places that would re-arm ask it first. It lives in the
/// App Group's defaults rather than the app's, because the extensions have to see it too.
///
/// Debug builds only. Nothing reads it in release: every call site is inside `#if DEBUG`,
/// so a shipped app has no way to be in this state at all.
nonisolated enum DebugKillSwitch {
    private static let key = "lockty.debug.enforcement-killed"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: SharedKeys.appGroupIdentifier)
    }

    /// Whether enforcement is being held down.
    static var isKilled: Bool {
        #if DEBUG
        return defaults?.bool(forKey: key) ?? false
        #else
        return false
        #endif
    }

    static func set(_ killed: Bool) {
        #if DEBUG
        defaults?.set(killed, forKey: key)
        #endif
    }
}
