import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        // Scheduled routines start here, with the app not running.
        RuntimeRepairCoordinator().startScheduledRoutineIfNeeded(for: activity)
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
            PauseAllowanceLiveActivityTermination.endAllDetached()
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
        // Never displace a routine the user already has running.
        guard runtimeState.activeRoutine == nil else { return }

        runtimeState.activeRoutine = snapshot.makeActiveRoutine(startedAt: Date())
        try? store.saveRuntimeState(runtimeState)
        print("Started scheduled routine \(snapshot.name) from the monitor extension")
        repairRuntimeState(activityName: activity.rawValue)
    }

    private func endScheduledRoutine(activityName: String) {
        guard let id = UUID(uuidString: String(activityName.dropFirst("lockty.routine.".count))),
              var runtimeState = try? store.loadRuntimeState(),
              runtimeState.activeRoutine?.routineID == id
        else { return }

        runtimeState.activeRoutine = nil
        runtimeState.activeBreak = nil
        runtimeState.activePauseAllowance = nil
        runtimeState.pendingPause = nil
        try? store.saveRuntimeState(runtimeState)
        PauseAllowanceLiveActivityTermination.endAllDetached()
        repairRuntimeState(activityName: activityName)
    }

    /// The allowance's usage threshold has been reached: the granted minutes have been
    /// spent, so it ends now whether or not its wall clock has run out.
    func repair(afterThresholdFor activity: DeviceActivityName, event: DeviceActivityEvent.Name) {
        _ = event
        if activity.rawValue.hasPrefix("lockty.pause.") {
            try? store.updateRuntimeState { state in
                state.activePauseAllowance = nil
                state.pendingPause = nil
            }
            // The countdown on the Lock Screen is the allowance. Reaching the threshold
            // is the allowance ending, so the activity has to end with it -- it used to
            // be left running against an allowance that no longer existed, still ticking
            // down over apps this call has already re-shielded.
            PauseAllowanceLiveActivityTermination.endAllDetached()
        }
        repairRuntimeState(activityName: activity.rawValue)
    }

    private func repairRuntimeState(activityName: String) {
        guard var runtimeState = try? store.loadRuntimeState() else { return }

        if activityName.hasPrefix("lockty.pause."),
           runtimeState.activePauseAllowance?.isExpired == true {
            runtimeState.activePauseAllowance = nil
            runtimeState.pendingPause = nil
            PauseAllowanceLiveActivityTermination.endAllDetached()
        }

        if activityName.hasPrefix("lockty.break."),
           let activeBreak = runtimeState.activeBreak,
           activeBreak.endsAt <= Date() {
            runtimeState.activeBreak = nil
            print("Break monitor expired breakID=\(activeBreak.id.uuidString) restoring active routine shields")
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

        let effectivePolicy = resolver.resolve(
            activeRoutine: runtimeState.activeRoutine,
            activeBreak: runtimeState.activeBreak,
            activePauseAllowance: runtimeState.livePauseAllowance,
            pauseRules: pauseRules
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
