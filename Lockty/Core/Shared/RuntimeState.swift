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
}

nonisolated enum RuntimeRecoveryFlag: String, Codable, Hashable {
    case shieldRestoreNeeded
    case expiredBreakNeedsFinalization
    case expiredPauseNeedsRelock
    case corruptedPayloadReset
}
