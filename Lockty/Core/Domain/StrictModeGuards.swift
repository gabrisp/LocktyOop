import Foundation

/// What Strict Mode actually prevents, chosen one door at a time.
///
/// Strict Mode used to be a single switch that meant one fixed thing: the routine could
/// not be edited while it ran. That is the weakest of the doors it could be closing --
/// someone who wants past a block does not edit the routine, they put the clock forward
/// an hour, or delete the app, or turn the whole thing off in Settings behind a passcode
/// they can change on the spot. Which of those to close is a real choice, and a different
/// one for each person, so it is asked rather than assumed.
///
/// Three of the four are enforced by iOS through ManagedSettings and hold even with the
/// app closed. The first is ours, and is enforced by the app refusing the edit.
nonisolated struct StrictModeGuards: Codable, Hashable, Sendable {
    /// Editing or deleting the routine while it is running.
    var preventsEditing: Bool
    /// Changing the clock, which is the simplest way past a schedule.
    var preventsDateAndTimeChanges: Bool
    /// Removing apps -- Lockty included, which is the other simplest way past it.
    var preventsAppRemoval: Bool
    /// Changing Face ID and the passcode, which is what guards Screen Time itself.
    var preventsPasscodeChanges: Bool

    init(
        preventsEditing: Bool = true,
        preventsDateAndTimeChanges: Bool = true,
        preventsAppRemoval: Bool = true,
        preventsPasscodeChanges: Bool = false
    ) {
        self.preventsEditing = preventsEditing
        self.preventsDateAndTimeChanges = preventsDateAndTimeChanges
        self.preventsAppRemoval = preventsAppRemoval
        self.preventsPasscodeChanges = preventsPasscodeChanges
    }

    /// What Strict Mode meant before it could be configured, so a routine saved then
    /// behaves exactly as it did.
    static let legacy = StrictModeGuards(
        preventsEditing: true,
        preventsDateAndTimeChanges: false,
        preventsAppRemoval: false,
        preventsPasscodeChanges: false
    )

    /// Nothing closed. What a routine that is not strict asks for.
    static let none = StrictModeGuards(
        preventsEditing: false,
        preventsDateAndTimeChanges: false,
        preventsAppRemoval: false,
        preventsPasscodeChanges: false
    )

    var isEmpty: Bool {
        !preventsEditing && !preventsDateAndTimeChanges && !preventsAppRemoval && !preventsPasscodeChanges
    }

    var enabledCount: Int {
        [preventsEditing, preventsDateAndTimeChanges, preventsAppRemoval, preventsPasscodeChanges]
            .filter { $0 }
            .count
    }

    /// The strictest of the two, door by door -- several routines can be running, and the
    /// device does what any one of them asked for.
    func union(_ other: StrictModeGuards) -> StrictModeGuards {
        StrictModeGuards(
            preventsEditing: preventsEditing || other.preventsEditing,
            preventsDateAndTimeChanges: preventsDateAndTimeChanges || other.preventsDateAndTimeChanges,
            preventsAppRemoval: preventsAppRemoval || other.preventsAppRemoval,
            preventsPasscodeChanges: preventsPasscodeChanges || other.preventsPasscodeChanges
        )
    }

    // Every field optional, and absent means the old behaviour rather than the new
    // default: a strict routine written before any of this existed only ever prevented
    // editing, and deciding for it that it also locks the passcode would be inventing a
    // restriction its owner never agreed to.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        preventsEditing = try container.decodeIfPresent(Bool.self, forKey: .preventsEditing) ?? true
        preventsDateAndTimeChanges = try container.decodeIfPresent(Bool.self, forKey: .preventsDateAndTimeChanges) ?? false
        preventsAppRemoval = try container.decodeIfPresent(Bool.self, forKey: .preventsAppRemoval) ?? false
        preventsPasscodeChanges = try container.decodeIfPresent(Bool.self, forKey: .preventsPasscodeChanges) ?? false
    }
}
