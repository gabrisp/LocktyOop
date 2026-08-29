import Foundation

struct ShieldPolicyResolver {
    func resolve(
        activeRoutine: ActiveRoutine?,
        activeBreak: ActiveBreak?,
        activePauseAllowance: ActivePauseAllowance?,
        pauseRules: [PauseRule]
    ) -> ShieldPolicy {
        var blockedApplications = Set<AppIdentity.ID>()
        var blockedDomains = Set<String>()
        var reasons: [ShieldReason] = []

        if let activeRoutine, activeBreak == nil {
            blockedApplications.formUnion(activeRoutine.shieldPolicy.blockedApplications)
            blockedDomains.formUnion(activeRoutine.shieldPolicy.blockedDomains)
            reasons.append(activeRoutine.shieldPolicy.reason)
        }

        let releasedApplications = activePauseAllowance?.releasedApplications ?? []

        let enabledPauseRules = pauseRules.filter(\.isEnabled)
        for rule in enabledPauseRules {
            let isTemporarilyAllowed = releasedApplications.contains(rule.application.id)
            if !isTemporarilyAllowed {
                blockedApplications.insert(rule.application.id)
                reasons.append(.pause(rule.application.id))
            }
        }

        // A granted allowance releases that app whatever put it behind the shield. The
        // loop above only skips it when it came from a pause rule, so an app blocked by
        // an active routine stayed shielded and "Continue" appeared to do nothing.
        var exemptApplications = Set<AppIdentity.ID>()
        for allowedAppID in releasedApplications {
            blockedApplications.remove(allowedAppID)
            exemptApplications.insert(allowedAppID)
        }

        let reason: ShieldReason
        switch reasons.count {
        case 0:
            reason = .none
        case 1:
            reason = reasons[0]
        default:
            reason = .combined
        }

        return ShieldPolicy(
            blockedApplications: blockedApplications,
            blockedDomains: blockedDomains,
            reason: reason,
            exemptApplications: exemptApplications
        )
    }
}
