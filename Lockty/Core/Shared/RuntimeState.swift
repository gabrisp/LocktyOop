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
    var activeRoutine: ActiveRoutine?
    var activeBreak: ActiveBreak?
    var pendingPause: PendingPauseContext?
    var activePauseAllowance: ActivePauseAllowance?

    var shieldPolicy: ShieldPolicy
    var pendingEvents: [PendingSystemEvent]
    var recoveryFlags: Set<RuntimeRecoveryFlag>
    var lastUpdatedAt: Date

    static let empty = RuntimeState(
        activeRoutine: nil,
        activeBreak: nil,
        pendingPause: nil,
        activePauseAllowance: nil,
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
}

nonisolated enum RuntimeRecoveryFlag: String, Codable, Hashable {
    case shieldRestoreNeeded
    case expiredBreakNeedsFinalization
    case expiredPauseNeedsRelock
    case corruptedPayloadReset
}
