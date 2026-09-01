import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        // Scheduled routines start here, with the app not running.
        RuntimeRepairCoordinator().startScheduledRoutineIfNeeded(for: activity)
        // And a daily-usage rule's budget is handed back here: this is the new day.
        RuntimeRepairCoordinator().resetRuleBudgetIfNeeded(for: activity)
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        RuntimeRepairCoordinator().repair(afterEnding: activity)
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        RuntimeRepairCoordinator().repair(afterThresholdFor: activity, event: event)
    }
}

private struct RuntimeRepairCoordinator {
    private let store = AppGroupStore()
    private let selectionStore = ScreenTimeSelectionStore()
    private let resolver = ShieldPolicyResolver()
    private let managedSettingsStore = ManagedSettingsStore(named: ManagedSettingsStore.Name("lockty"))

    func repair(afterEnding activity: DeviceActivityName) {
        if activity.rawValue.hasPrefix("lockty.routine.") {
            endScheduledRoutine(activityName: activity.rawValue)
            return
        }

        // An allowance's window is scheduled to end on its expiry, so this is the moment
        // it runs out -- not a moment to go and check whether it has. Asking isExpired
        // here missed the ones the system delivered a second early, and then nothing
        // relocked until something else noticed.
        if activity.rawValue.hasPrefix("lockty.pause.") {
            try? store.updateRuntimeState { state in
                state.activePauseAllowance = nil
                state.pendingPause = nil
            }
            PauseAllowanceLiveActivityTermination.endAllBlocking()
        }

        repairRuntimeState(activityName: activity.rawValue)
    }

    /// The schedule is a plain daily window (DeviceActivity has no weekday filter), so
    /// the configured weekdays are checked here before anything is applied.
    func startScheduledRoutineIfNeeded(for activity: DeviceActivityName) {
        guard activity.rawValue.hasPrefix("lockty.routine."),
              let id = UUID(uuidString: String(activity.rawValue.dropFirst("lockty.routine.".count))),
              let snapshot = store.loadRoutineScheduleSnapshots().first(where: { $0.id == id })
        else { return }

        let weekday = Weekday(rawValue: Calendar.current.component(.weekday, from: Date()))
        guard let weekday, snapshot.schedule.weekdays.contains(weekday) else {
            print("Scheduled routine \(snapshot.name) skipped: not scheduled for today")
            return
        }

        guard var runtimeState = try? store.loadRuntimeState() else { return }
        // Alongside whatever else is running, not instead of it. This used to bail out
        // whenever anything was active, so a routine whose window overlapped another's
        // was dropped at its start and never reconsidered -- it lost its entire window
        // without a word. Only starting the same routine twice is refused.
        guard !runtimeState.activeRoutines.contains(where: { $0.routineID == id }) else { return }

        runtimeState.activeRoutines.append(snapshot.makeActiveRoutine(startedAt: Date()))
        try? store.saveRuntimeState(runtimeState)
        print("Started scheduled routine \(snapshot.name) from the monitor extension")
        repairRuntimeState(activityName: activity.rawValue)
    }

    /// A new day for a daily-usage rule: the interval it was budgeted against has just
    /// restarted, so whatever it spent yesterday stops shielding anything.
    ///
    /// The record is cleared rather than left to age out, because the shield has to come
    /// down here and now -- a stale record that merely *reads* as a different day would
    /// not be re-applied until something else recomputed the policy.
    func resetRuleBudgetIfNeeded(for activity: DeviceActivityName) {
        guard let ruleID = Self.ruleID(from: activity) else { return }

        try? store.updateRuleEnforcementState { state in
            state.records[ruleID] = nil
        }
        print("Rule \(ruleID.uuidString) budget reset for a new day")
        repairRuntimeState(activityName: activity.rawValue)
    }

    private static func ruleID(from activity: DeviceActivityName) -> UUID? {
        let prefix = "lockty.rule."
        guard activity.rawValue.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(activity.rawValue.dropFirst(prefix.count)))
    }

    /// Ends one scheduled routine, leaving any others running.
    ///
    /// Only this routine and its own break are removed. The shield is then recomputed
    /// from what is left, which is what frees exactly the apps this routine was holding:
    /// one that another running routine also blocks stays blocked, because that routine
    /// is still in the union.
    private func endScheduledRoutine(activityName: String) {
        guard let id = UUID(uuidString: String(activityName.dropFirst("lockty.routine.".count))),
              var runtimeState = try? store.loadRuntimeState(),
              runtimeState.activeRoutines.contains(where: { $0.routineID == id })
        else { return }

        runtimeState.activeRoutines.removeAll { $0.routineID == id }
        runtimeState.activeBreaks.removeAll { $0.routineID == id }

        // The allowance and the request the shield was waiting on belong to the session
        // as a whole, so they only go once there is no session left to belong to.
        if runtimeState.activeRoutines.isEmpty {
            runtimeState.activePauseAllowance = nil
            runtimeState.pendingPause = nil
            PauseAllowanceLiveActivityTermination.endAllBlocking()
        }

        try? store.saveRuntimeState(runtimeState)
        repairRuntimeState(activityName: activityName)
    }

    /// The allowance's usage threshold has been reached: the granted minutes have been
    /// spent, so it ends now whether or not its wall clock has run out.
    func repair(afterThresholdFor activity: DeviceActivityName, event: DeviceActivityEvent.Name) {
        _ = event
        // A daily-usage rule has spent the minutes it was given. Marking it here is what
        // puts its apps behind the shield, since repairRuntimeState below recomputes the
        // policy from exactly this record.
        if let ruleID = Self.ruleID(from: activity) {
            try? store.updateRuleEnforcementState { state in
                state.update(ruleID) { record in
                    record.usageLimitReachedAt = Date()
                }
            }
            print("Rule \(ruleID.uuidString) reached its daily usage limit")
        }

        if activity.rawValue.hasPrefix("lockty.pause.") {
            try? store.updateRuntimeState { state in
                state.activePauseAllowance = nil
                state.pendingPause = nil
            }
            // The countdown on the Lock Screen is the allowance. Reaching the threshold
            // is the allowance ending, so the activity has to end with it -- it used to
            // be left running against an allowance that no longer existed, still ticking
            // down over apps this call has already re-shielded.
            PauseAllowanceLiveActivityTermination.endAllBlocking()
        }
        repairRuntimeState(activityName: activity.rawValue)
    }

    private func repairRuntimeState(activityName: String) {
        guard var runtimeState = try? store.loadRuntimeState() else { return }

        if activityName.hasPrefix("lockty.pause."),
           runtimeState.activePauseAllowance?.isExpired == true {
            runtimeState.activePauseAllowance = nil
            runtimeState.pendingPause = nil
            PauseAllowanceLiveActivityTermination.endAllBlocking()
        }

        if activityName.hasPrefix("lockty.break.") {
            // Each expired break is dropped on its own. They belong to different
            // routines, and clearing them wholesale would put back the blocks of a
            // routine whose break is still running.
            for expired in runtimeState.activeBreaks.filter({ $0.endsAt <= Date() }) {
                runtimeState.activeBreaks.removeAll { $0.id == expired.id }
                print("Break monitor expired breakID=\(expired.id.uuidString) restoring routine \(expired.routineID.uuidString) shields")
            }
        }

        let pauseRules = store.loadPauseRuleSnapshots()
            .filter(\.isEnabled)
            .map {
                PauseRule(
                    id: $0.id,
                    application: $0.application,
                    isEnabled: $0.isEnabled,
                    steps: $0.steps,
                    allowanceDuration: $0.allowanceDuration,
                    relockAfterAllowance: $0.relockAfterAllowance,
                    createdAt: $0.updatedAt,
                    updatedAt: $0.updatedAt
                )
            }

        let shieldRules = store.loadShieldRules()

        let effectivePolicy = resolver.resolve(
            activeRoutines: runtimeState.activeRoutines,
            activeBreaks: runtimeState.activeBreaks,
            activePauseAllowance: runtimeState.livePauseAllowance,
            pauseRules: pauseRules,
            rules: shieldRules.rules,
            ruleEnforcement: shieldRules.enforcement,
                alwaysAllowedApplications: store.loadAlwaysAllowedApplications()
        )

        runtimeState.shieldPolicy = effectivePolicy
        runtimeState.recoveryFlags = []

        let store = AppGroupStore()
        try? store.saveRuntimeState(runtimeState)
        apply(policy: effectivePolicy)
    }

    private func apply(policy: ShieldPolicy) {
        var selection = (try? selectionStore.selection(for: policy)) ?? FamilyActivitySelection()
        let blockedDomains = Set(policy.blockedDomains.map(ManagedSettings.WebDomain.init(domain:)))

        // Same exemption the app applies: an app released by a live pause allowance must
        // not be re-shielded here, whether it is blocked by token or by category.
        let exemptTokens = selectionStore.applicationTokens(for: policy.exemptApplications)
        selection.applicationTokens.subtract(exemptTokens)

        print(
            """
            Monitor extension applying policy reason=\(String(describing: policy.reason)) \
            apps=\(selection.applicationTokens.count) \
            categories=\(selection.categoryTokens.count) \
            domains=\(selection.webDomainTokens.count) \
            manualDomains=\(blockedDomains.count) \
            exempt=\(exemptTokens.count)
            """
        )

        managedSettingsStore.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        managedSettingsStore.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        managedSettingsStore.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens, except: exemptTokens)
        managedSettingsStore.webContent.blockedByFilter = blockedDomains.isEmpty ? nil : .specific(blockedDomains)
    }

    func markShieldRestoreNeeded() {
        try? store.updateRuntimeState { state in
            state.recoveryFlags.insert(.shieldRestoreNeeded)
        }
    }

    func markExpiredRuntimeNeedsRepair() {
        try? store.updateRuntimeState { state in
            state.recoveryFlags.insert(.expiredPauseNeedsRelock)
            state.recoveryFlags.insert(.expiredBreakNeedsFinalization)
        }
    }
}
