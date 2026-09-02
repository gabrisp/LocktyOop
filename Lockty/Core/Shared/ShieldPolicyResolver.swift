import Foundation

struct ShieldPolicyResolver {
    /// The shield as the union of everything that wants something blocked.
    ///
    /// Recomputed from scratch every time rather than added to and subtracted from, which
    /// is what makes a routine ending clean up after itself: it is simply no longer in
    /// `activeRoutines`, so its apps fall out of the union -- and an app that a *second*
    /// routine also blocks stays blocked, because that routine is still in it. Nothing
    /// has to work out which apps belonged to whom.
    ///
    /// A break is per routine and lifts only the routine that granted it. Two routines
    /// blocking the same app means taking a break on one of them changes nothing for that
    /// app: the other never agreed to let it out.
    func resolve(
        activeRoutines: [ActiveRoutine],
        activeBreaks: [ActiveBreak],
        activePauseAllowance: ActivePauseAllowance?,
        pauseRules: [PauseRule],
        rules: [Rule] = [],
        ruleEnforcement: RuleEnforcementState = .empty,
        alwaysAllowedApplications: Set<AppIdentity.ID> = []
    ) -> ShieldPolicy {
        var blockedApplications = Set<AppIdentity.ID>()
        var blockedDomains = Set<String>()
        var contentRestrictions = ContentRestrictions.none
        var reasons: [ShieldReason] = []
        var selectionScopes = Set<ScreenTimeSelectionScope>()

        let routineIDsOnBreak = Set(activeBreaks.map(\.routineID))

        for activeRoutine in activeRoutines where !routineIDsOnBreak.contains(activeRoutine.routineID) {
            blockedApplications.formUnion(activeRoutine.shieldPolicy.blockedApplications)
            blockedDomains.formUnion(activeRoutine.shieldPolicy.blockedDomains)
            contentRestrictions = contentRestrictions.union(activeRoutine.shieldPolicy.contentRestrictions)
            reasons.append(activeRoutine.shieldPolicy.reason)
            selectionScopes.formUnion(activeRoutine.shieldPolicy.selectionScopes)
        }

        // The rules that are not routines. A schedule rule *is* the active routine above;
        // the limits carry their own answer to whether they are blocking right now, and
        // a break does not lift them -- a break belongs to the routine that granted it.
        for rule in rules where rule.isShielding(given: ruleEnforcement) {
            blockedApplications.formUnion(rule.blockedApplications)
            blockedDomains.formUnion(rule.blockedDomains)
            reasons.append(.rule(rule.id))
            selectionScopes.formUnion(rule.selectionScopes)
        }

        let releasedApplications = activePauseAllowance?.releasedApplications ?? []

        let enabledPauseRules = pauseRules.filter(\.isEnabled)
        for rule in enabledPauseRules {
            let isTemporarilyAllowed = releasedApplications.contains(rule.application.id)
            if !isTemporarilyAllowed {
                blockedApplications.insert(rule.application.id)
                reasons.append(.pause(rule.application.id))
                selectionScopes.insert(.pause(rule.id))
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

        // Always Allowed, applied after everything else because it has to win against
        // everything else. Dropping these from `blockedApplications` is not enough on its
        // own: the usual way one of them gets caught is a rule blocking a whole category
        // it happens to sit in, and no app token was ever listed to remove. Carrying them
        // as exemptions is what reaches the category shield's `except:` list.
        for allowedAppID in alwaysAllowedApplications {
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
            selectionScopes: selectionScopes,
            exemptApplications: exemptApplications,
            contentRestrictions: contentRestrictions
        )
    }
}
