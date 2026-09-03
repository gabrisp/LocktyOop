import Foundation

/// What AutoFocus says when it steps in, and how long it waits before it does.
///
/// AutoFocus knew which apps distract and how hard to intervene, and then intervened
/// never: nothing was monitored and nothing was said. The detection is a usage threshold
/// over the distracting apps -- the one thing Screen Time will measure in the background
/// -- and the intervention is a line delivered at the moment it trips.
nonisolated enum AutoFocusIntervention {
    /// How long inside the distracting apps before it says anything.
    ///
    /// Not a setting of its own: the intervention level already says how strongly you
    /// want to be interrupted, and asking for both a level and a number is asking the
    /// same question twice.
    static func thresholdMinutes(for level: AutoFocusInterventionLevel) -> Int {
        switch level {
        case .low: 45
        case .medium: 25
        case .high: 12
        }
    }

    /// How long it stays quiet afterwards.
    ///
    /// Derived from the level rather than set beside it. "How often does this interrupt
    /// me" is one question, and it was being asked twice -- once as a threshold and once
    /// as a cooldown -- which let the two be set against each other: a high level with a
    /// four-hour gap is not a high level.
    static func cooldownMinutes(for level: AutoFocusInterventionLevel) -> Int {
        switch level {
        case .low: 120
        case .medium: 60
        case .high: 30
        }
    }

    /// The lines. Written to be read on a lock screen mid-scroll, which rules out
    /// anything long, anything scolding, and anything that reads as a notification from
    /// the very kind of app it is about.
    ///
    /// A question more often than an instruction: "stop" is easy to dismiss, and "is this
    /// what you sat down to do" is harder to answer while still scrolling.
    static let lines: [String] = [
        "Still here. Is this what you sat down to do?",
        "That is %@ in. Worth checking you meant to.",
        "%@ gone. Nothing new has happened since you started.",
        "You have been here %@. What were you about to do instead?",
        "%@ in, and the feed has no end. You do.",
        "A good moment to stop is any moment. This one works."
    ]

    /// The line for a given elapsed time, with the duration filled in where the line
    /// wants it.
    ///
    /// Chosen by the minute rather than at random, so two notifications a few seconds
    /// apart cannot say the same thing twice -- and so the same phrasing does not come up
    /// every single time the threshold trips.
    static func line(minutes: Int, durationText: String) -> String {
        let index = abs(minutes.hashValue) % lines.count
        return String(format: lines[index], durationText)
    }

    static let title = "AutoFocus"
    /// The name of the usage event, and of the activity it belongs to.
    static let activityName = "lockty.autofocus"
    static let eventName = "lockty.autofocus.usage"
}
