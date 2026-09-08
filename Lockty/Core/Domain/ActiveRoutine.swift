import Foundation

nonisolated struct ActiveRoutine: Codable, Hashable, Identifiable {
    let id: UUID
    var routineID: UUID
    var nameSnapshot: String
    /// The routine's icon at the time it started, so anything showing the running
    /// session can render it without loading the routine back from storage.
    var iconSnapshot: String?
    var modeSnapshot: RoutineMode
    /// The routine's colour when it started. Snapshotted with the name and the icon, for
    /// the same reason: anything showing a running routine can draw it without loading
    /// the routine back from storage -- and the extensions cannot load it at all.
    var colorSnapshot: RoutineColor
    var startedAt: Date
    var expectedEndAt: Date?
    var trigger: RoutineTrigger
    var shieldPolicy: ShieldPolicy
    var breakPolicySnapshot: BreakPolicy
    /// The pause this routine offers, carried here so the shield extension can build the
    /// flow without reaching into Core Data.
    var pausePolicySnapshot: RoutinePausePolicy
    var taskCompletions: [RoutineTaskCompletion]
    var allowsPauseDuringStrictMode: Bool

    init(
        id: UUID = UUID(),
        routineID: UUID,
        nameSnapshot: String,
        iconSnapshot: String? = nil,
        modeSnapshot: RoutineMode,
        colorSnapshot: RoutineColor = .mint,
        startedAt: Date,
        expectedEndAt: Date? = nil,
        trigger: RoutineTrigger,
        shieldPolicy: ShieldPolicy,
        breakPolicySnapshot: BreakPolicy,
        pausePolicySnapshot: RoutinePausePolicy = .off,
        taskCompletions: [RoutineTaskCompletion],
        allowsPauseDuringStrictMode: Bool
    ) {
        self.id = id
        self.routineID = routineID
        self.nameSnapshot = nameSnapshot
        self.iconSnapshot = iconSnapshot
        self.modeSnapshot = modeSnapshot
        self.colorSnapshot = colorSnapshot
        self.startedAt = startedAt
        self.expectedEndAt = expectedEndAt
        self.trigger = trigger
        self.shieldPolicy = shieldPolicy
        self.breakPolicySnapshot = breakPolicySnapshot
        self.pausePolicySnapshot = pausePolicySnapshot
        self.taskCompletions = taskCompletions
        self.allowsPauseDuringStrictMode = allowsPauseDuringStrictMode
    }

    // Written by hand so a runtime state persisted before pausePolicySnapshot existed
    // still decodes. Without it the whole RuntimeState fails to load and the running
    // routine is silently dropped on the next launch.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        routineID = try container.decode(UUID.self, forKey: .routineID)
        nameSnapshot = try container.decode(String.self, forKey: .nameSnapshot)
        iconSnapshot = try container.decodeIfPresent(String.self, forKey: .iconSnapshot)
        modeSnapshot = try container.decode(RoutineMode.self, forKey: .modeSnapshot)
        // A session written before the colour was snapshotted keeps running rather than
        // failing to decode; mint is the routine default, so it is what it would have
        // been given anyway.
        colorSnapshot = try container.decodeIfPresent(RoutineColor.self, forKey: .colorSnapshot) ?? .mint
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        expectedEndAt = try container.decodeIfPresent(Date.self, forKey: .expectedEndAt)
        trigger = try container.decode(RoutineTrigger.self, forKey: .trigger)
        shieldPolicy = try container.decode(ShieldPolicy.self, forKey: .shieldPolicy)
        breakPolicySnapshot = try container.decode(BreakPolicy.self, forKey: .breakPolicySnapshot)
        // Defaults to the standard flow, not off: there is no UI to configure a pause
        // yet, so a routine that predates the field must still be unlockable.
        pausePolicySnapshot = try container.decodeIfPresent(RoutinePausePolicy.self, forKey: .pausePolicySnapshot) ?? .off
        taskCompletions = try container.decode([RoutineTaskCompletion].self, forKey: .taskCompletions)
        allowsPauseDuringStrictMode = try container.decode(Bool.self, forKey: .allowsPauseDuringStrictMode)
    }
}

/// Which routine answers for an app, when several are holding it at once.
///
/// Overlapping routines are the point, and two of them can hold the same app with
/// different break policies. Something has to decide whose friction you walk and whose
/// break limit applies, and every screen that needed the answer was working it out for
/// itself: some took the first to have started, one took the strictest, and they
/// disagreed -- so the app could offer a friction that the unlock would then refuse.
extension Collection where Element == ActiveRoutine {
    /// The routine whose policy governs: the last to have started.
    ///
    /// The later routine is the more deliberate one. Taking the first meant a routine set
    /// up weeks ago decided what the one started a minute ago would allow -- so a routine
    /// that offers no unlocks silenced a newer one that does.
    var governingRoutine: ActiveRoutine? {
        self.max { $0.startedAt < $1.startedAt }
    }

    /// The strict routine among them, if there is one.
    ///
    /// It answers before the others because it is the strictest of them: starting a looser
    /// routine beside a strict one must not become the way to be governed by the looser
    /// one's policy.
    ///
    /// Answering is not refusing. Strict mode is the promise that a routine cannot be
    /// *ended* early -- that is the whole of what it means -- and it says nothing about
    /// breaks. A strict routine that was set up with a friction is meant to have it, so it
    /// answers with its own break policy like any other.
    var strictRoutine: ActiveRoutine? {
        first { $0.modeSnapshot == .strict }
    }

    /// The one that answers: the strict routine if there is one, otherwise the most
    /// recent. What it then allows is its own break policy's business.
    var routineAnsweringForApp: ActiveRoutine? {
        strictRoutine ?? governingRoutine
    }
}
