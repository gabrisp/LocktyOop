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
        case .stopRoutine, .editRoutine, .deleteRoutine, .modifyBlockedApplications, .modifyDomains, .changePauseRule:
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
