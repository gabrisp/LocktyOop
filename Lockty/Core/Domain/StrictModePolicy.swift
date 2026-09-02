import Foundation

enum StrictModeAction: String, Codable, CaseIterable, Hashable {
    case stopRoutine
    case editRoutine
    case deleteRoutine
    case modifyBlockedApplications
    case modifyDomains
    case startBreak
    case usePause
    case changePauseRule
    case receiveAnotherTrigger
}

struct StrictModeDecision: Codable, Hashable {
    var isAllowed: Bool
    var reason: String?

    static let allowed = StrictModeDecision(isAllowed: true, reason: nil)

    static func denied(_ reason: String) -> StrictModeDecision {
        StrictModeDecision(isAllowed: false, reason: reason)
    }
}

struct StrictModePolicy {
    func decision(for action: StrictModeAction, activeRoutine: ActiveRoutine?) -> StrictModeDecision {
        guard let activeRoutine, activeRoutine.modeSnapshot == .strict else {
            return .allowed
        }

        switch action {
        case .stopRoutine:
            return .allowed

        case .editRoutine, .deleteRoutine, .modifyBlockedApplications, .modifyDomains, .changePauseRule:
            // The one door Strict Mode closes by itself rather than through
            // ManagedSettings, and now the one it can be told to leave open: someone who
            // locked the clock and the App Store may still want to fix a typo in the
            // routine's name.
            guard activeRoutine.shieldPolicy.strictGuards.preventsEditing else { return .allowed }
            return .denied("This routine is running in Strict Mode.")

        case .startBreak:
            return .allowed

        case .usePause:
            return activeRoutine.allowsPauseDuringStrictMode
                ? .allowed
                : .denied("Pause is disabled for this Strict routine.")

        case .receiveAnotherTrigger:
            return .denied("Another routine cannot replace an active Strict routine.")
        }
    }
}
