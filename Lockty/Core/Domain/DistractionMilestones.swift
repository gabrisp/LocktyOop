import Foundation

/// The notices that arrive as a day in distracting apps piles up.
///
/// One per threshold rather than one a day. Fifteen minutes and ninety minutes are not
/// the same fact about an afternoon, and a single notification set at whichever number
/// somebody chose in a menu can only ever say one of them.
///
/// Each is a usage threshold registered with DeviceActivity, so iOS counts the minutes
/// and launches the monitor extension the moment one is crossed -- with Lockty closed,
/// with nothing polling, with nothing to be woken up.
///
/// The lines are the whole point of the feature. They do not scold and they do not
/// congratulate: they say the figure, and then they leave a door open. Somebody reading
/// this has already decided these apps are a problem -- being told off for it is the one
/// thing that would make them turn the notifications off.
nonisolated enum DistractionMilestones {
    struct Milestone: Hashable, Identifiable {
        let minutes: Int
        let title: String
        let body: String

        var id: Int { minutes }
        /// The event name this milestone is registered under.
        var eventName: String { "\(DistractionMilestones.eventPrefix)\(minutes)" }
    }

    static let eventPrefix = "lockty.autofocus.usage."

    /// The minutes a milestone fired at, read back off the event name.
    static func minutes(from eventName: String) -> Int? {
        guard eventName.hasPrefix(eventPrefix) else { return nil }
        return Int(eventName.dropFirst(eventPrefix.count))
    }

    static func milestone(forEvent eventName: String) -> Milestone? {
        guard let minutes = minutes(from: eventName) else { return nil }
        return all.first { $0.minutes == minutes }
    }

    /// Every step there is. Which of them are actually registered depends on the level.
    static let all: [Milestone] = [
        Milestone(
            minutes: 5,
            title: "Five minutes in",
            body: "Over 5 min in distracting apps today. This is still easy to reset."
        ),
        Milestone(
            minutes: 10,
            title: "Ten minutes in",
            body: "Over 10 min in distracting apps today. Worth checking you meant to stay."
        ),
        Milestone(
            minutes: 15,
            title: "It is adding up",
            body: "Over 15 min in distracting apps today. A small reset still counts."
        ),
        Milestone(
            minutes: 30,
            title: "Half an hour in",
            body: "Over 30 min today. A good moment to close the tab."
        ),
        Milestone(
            minutes: 45,
            title: "A heavy screen day?",
            body: "Over 45 min in distracting apps. Make the next minute an offline one."
        ),
        Milestone(
            minutes: 60,
            title: "An hour gone",
            body: "An hour today in apps you called distracting. Nothing new has happened since you started."
        )
    ]

    /// Which milestones a level is worth being interrupted by.
    ///
    /// The level was a single threshold and a cooldown; it is now how often you want to
    /// hear from the app at all. Low speaks twice in a heavy day, high speaks at every
    /// step -- and nobody is told anything twice, because a threshold fires once per day
    /// by construction.
    static func milestones(for level: AutoFocusInterventionLevel) -> [Milestone] {
        switch level {
        case .low: all.filter { $0.minutes >= 30 }
        case .medium: all.filter { [10, 15, 30, 60].contains($0.minutes) }
        case .high: all
        }
    }
}
