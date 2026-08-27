import DeviceActivity
import Foundation
import ManagedSettings

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
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
        repairRuntimeState(activityName: activity.rawValue)
    }

    func repair(afterThresholdFor activity: DeviceActivityName, event: DeviceActivityEvent.Name) {
        _ = event
        repairRuntimeState(activityName: activity.rawValue)
    }

    private func repairRuntimeState(activityName: String) {
        guard var runtimeState = try? store.loadRuntimeState() else { return }

        if activityName.hasPrefix("lockty.pause."),
           runtimeState.activePauseAllowance?.isExpired == true {
            runtimeState.activePauseAllowance = nil
            runtimeState.pendingPause = nil
        }

        if activityName.hasPrefix("lockty.break."),
           let activeBreak = runtimeState.activeBreak,
           activeBreak.endsAt <= Date() {
            runtimeState.activeBreak = nil

            if runtimeState.activeRoutine?.modeSnapshot == .strict {
                runtimeState.activeRoutine = nil
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

        let effectivePolicy = resolver.resolve(
            activeRoutine: runtimeState.activeRoutine,
            activeBreak: runtimeState.activeBreak,
            activePauseAllowance: runtimeState.activePauseAllowance,
            pauseRules: pauseRules
        )

        runtimeState.shieldPolicy = effectivePolicy
        runtimeState.recoveryFlags = []

        let store = AppGroupStore()
        try? store.saveRuntimeState(runtimeState)
        apply(policy: effectivePolicy)
    }

    private func apply(policy: ShieldPolicy) {
        let selection = selectionStore.mergedSelection(for: policy)
        let blockedDomains = Set(policy.blockedDomains.map(ManagedSettings.WebDomain.init(domain:)))

        managedSettingsStore.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        managedSettingsStore.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        managedSettingsStore.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
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
