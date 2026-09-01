import Foundation

/// The breathe every unlock opens on.
///
/// One place for its bounds, because three different screens offer to change it and the
/// unlock flow has to trust whatever they stored: a value clamped in the editor but not
/// on the way out would let an old or hand-edited flow open on a breathe of nothing.
nonisolated enum LocktyBreathe {
    /// Long enough to be a pause rather than a flicker.
    static let minimumSeconds = 5
    /// Past three minutes it stops being a breath before acting and becomes a punishment,
    /// which is a different feature.
    static let maximumSeconds = 180

    static func clamped(_ seconds: Int) -> Int {
        min(max(seconds, minimumSeconds), maximumSeconds)
    }

    /// "1:30", or "45s" under a minute -- a bare "90" reads as neither.
    static func label(_ seconds: Int) -> String {
        let clamped = clamped(seconds)
        guard clamped >= 60 else { return "\(clamped)s" }
        return String(format: "%d:%02d", clamped / 60, clamped % 60)
    }
}
