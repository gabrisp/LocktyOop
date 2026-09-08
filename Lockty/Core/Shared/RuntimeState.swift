import Foundation

nonisolated struct RuntimeEnvelope: Codable, Hashable {
    var schemaVersion: Int
    var writtenAt: Date
    var state: RuntimeState

    static let currentSchemaVersion = 1

    nonisolated static func current(_ state: RuntimeState) -> RuntimeEnvelope {
        RuntimeEnvelope(
            schemaVersion: currentSchemaVersion,
            writtenAt: Date(),
            state: state
        )
    }
}

nonisolated struct RuntimeState: Codable, Hashable {
    /// Every routine running right now, in the order they started.
    ///
    /// A list, not one slot. Routines are allowed to overlap -- two schedules covering
    /// the same hours are a normal thing to want -- and with a single slot the second
    /// one to come round was simply dropped, for good: nothing re-checked it when the
    /// first ended, so it lost its whole window without a word.
    var activeRoutines: [ActiveRoutine]
    /// The breaks running right now, at most one per routine.
    ///
    /// Each carries its own `routineID`, which is what makes a break belong to something:
    /// it lifts the routine that granted it and nothing else. An app another routine also
    /// blocks stays blocked, because that other routine never agreed to let it out.
    var activeBreaks: [ActiveBreak]
    var pendingPause: PendingPauseContext?
    var activePauseAllowance: ActivePauseAllowance?

    /// What each running routine will still allow, keyed by routine.
    ///
    /// Worked out by the app and left here for the extensions, which need the answer and
    /// cannot reach it: the count of breaks already taken lives in Core Data, and an
    /// extension has no Core Data. Without it the shield could only ever ask "does this
    /// routine allow breaks at all", so a routine that allowed two and had spent both
    /// still wrote "Unlock with Lockty" on its button -- and pressing it opened the app to
    /// be told no.
    var breakAvailabilities: [UUID: StoredBreakAvailability]

    var shieldPolicy: ShieldPolicy
    var pendingEvents: [PendingSystemEvent]
    var recoveryFlags: Set<RuntimeRecoveryFlag>
    var lastUpdatedAt: Date

    static let empty = RuntimeState(
        activeRoutines: [],
        activeBreaks: [],
        pendingPause: nil,
        activePauseAllowance: nil,
        breakAvailabilities: [:],
        shieldPolicy: .empty,
        pendingEvents: [],
        recoveryFlags: [],
        lastUpdatedAt: Date()
    )

    /// The allowance only if it is still running.
    ///
    /// Everything that resolves a shield policy has to use this rather than the stored
    /// property: an expired allowance kept exempting its app, so once one had been used
    /// the Pause never re-shielded that app again -- stopping a routine included.
    var livePauseAllowance: ActivePauseAllowance? {
        activePauseAllowance.flatMap { $0.isExpired ? nil : $0 }
    }

    /// The break belonging to a given routine, if it is on one.
    func activeBreak(for routineID: UUID) -> ActiveBreak? {
        activeBreaks.first { $0.routineID == routineID }
    }

    func activeRoutine(id: UUID) -> ActiveRoutine? {
        activeRoutines.first { $0.routineID == id }
    }

    /// The routine to put in front of the user when only one can be shown. The first to
    /// have started, so the answer doesn't reshuffle as others come and go.
    var primaryActiveRoutine: ActiveRoutine? {
        activeRoutines.min { $0.startedAt < $1.startedAt }
    }

    // Written by hand so a runtime state saved when these were single values still
    // decodes. Without it every routine and break in flight at the moment of the update
    // would throw on the next read and be reset away.
    private enum CodingKeys: String, CodingKey {
        case activeRoutines, activeBreaks, activeRoutine, activeBreak
        case pendingPause, activePauseAllowance, breakAvailabilities, shieldPolicy
        case pendingEvents, recoveryFlags, lastUpdatedAt
    }

    init(
        activeRoutines: [ActiveRoutine],
        activeBreaks: [ActiveBreak],
        pendingPause: PendingPauseContext?,
        activePauseAllowance: ActivePauseAllowance?,
        breakAvailabilities: [UUID: StoredBreakAvailability] = [:],
        shieldPolicy: ShieldPolicy,
        pendingEvents: [PendingSystemEvent],
        recoveryFlags: Set<RuntimeRecoveryFlag>,
        lastUpdatedAt: Date
    ) {
        self.activeRoutines = activeRoutines
        self.activeBreaks = activeBreaks
        self.pendingPause = pendingPause
        self.activePauseAllowance = activePauseAllowance
        self.breakAvailabilities = breakAvailabilities
        self.shieldPolicy = shieldPolicy
        self.pendingEvents = pendingEvents
        self.recoveryFlags = recoveryFlags
        self.lastUpdatedAt = lastUpdatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let routines = try container.decodeIfPresent([ActiveRoutine].self, forKey: .activeRoutines) {
            activeRoutines = routines
        } else {
            activeRoutines = try container
                .decodeIfPresent(ActiveRoutine.self, forKey: .activeRoutine)
                .map { [$0] } ?? []
        }

        if let breaks = try container.decodeIfPresent([ActiveBreak].self, forKey: .activeBreaks) {
            activeBreaks = breaks
        } else {
            activeBreaks = try container
                .decodeIfPresent(ActiveBreak.self, forKey: .activeBreak)
                .map { [$0] } ?? []
        }

        pendingPause = try container.decodeIfPresent(PendingPauseContext.self, forKey: .pendingPause)
        activePauseAllowance = try container.decodeIfPresent(ActivePauseAllowance.self, forKey: .activePauseAllowance)
        breakAvailabilities = try container
            .decodeIfPresent([UUID: StoredBreakAvailability].self, forKey: .breakAvailabilities) ?? [:]
        shieldPolicy = try container.decode(ShieldPolicy.self, forKey: .shieldPolicy)
        pendingEvents = try container.decode([PendingSystemEvent].self, forKey: .pendingEvents)
        recoveryFlags = try container.decode(Set<RuntimeRecoveryFlag>.self, forKey: .recoveryFlags)
        lastUpdatedAt = try container.decode(Date.self, forKey: .lastUpdatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(activeRoutines, forKey: .activeRoutines)
        try container.encode(activeBreaks, forKey: .activeBreaks)
        try container.encodeIfPresent(pendingPause, forKey: .pendingPause)
        try container.encodeIfPresent(activePauseAllowance, forKey: .activePauseAllowance)
        try container.encode(breakAvailabilities, forKey: .breakAvailabilities)
        try container.encode(shieldPolicy, forKey: .shieldPolicy)
        try container.encode(pendingEvents, forKey: .pendingEvents)
        try container.encode(recoveryFlags, forKey: .recoveryFlags)
        try container.encode(lastUpdatedAt, forKey: .lastUpdatedAt)
    }
}

nonisolated enum RuntimeRecoveryFlag: String, Codable, Hashable {
    case shieldRestoreNeeded
    case expiredBreakNeedsFinalization
    case expiredPauseNeedsRelock
    case corruptedPayloadReset
}

/// What one routine will still allow, as a fact an extension can read.
///
/// A photograph, not a source: the app works this out from the break policy and the run's
/// own history, and writes it down. Nothing else may compute from it, and it is only ever
/// as fresh as the last time the app recomputed the shield -- which is after every change
/// that could move it.
nonisolated struct StoredBreakAvailability: Codable, Hashable {
    /// Whether the routine offers breaks at all.
    var offersBreaks: Bool
    /// How many are left in this run. Nil for unlimited.
    var remaining: Int?
    /// When the next one may be taken, while a cooldown is running.
    var retryAt: Date?

    init(offersBreaks: Bool, remaining: Int? = nil, retryAt: Date? = nil) {
        self.offersBreaks = offersBreaks
        self.remaining = remaining
        self.retryAt = retryAt
    }

    /// Whether asking right now would be answered with a yes.
    func isAvailable(at date: Date = Date()) -> Bool {
        guard offersBreaks else { return false }
        if let remaining, remaining <= 0 { return false }
        if let retryAt, date < retryAt { return false }
        return true
    }
}
