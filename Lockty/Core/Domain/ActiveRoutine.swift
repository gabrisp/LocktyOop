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
