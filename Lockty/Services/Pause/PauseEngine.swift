import Foundation
import Observation
import UserNotifications

enum PauseEngineState: Equatable {
    case idle
    case requested(PauseContext)
    case thinking(PauseContext, remainingSeconds: Int)
    case decision(PauseContext)
    case temporarilyAllowed(ActivePauseAllowance)
    case relocking(PauseContext)
    case locked(PauseContext)
    case cancelled(PauseContext)
    case failed(String)
}

@Observable
final class PauseEngine {
    private let shieldService: ShieldServicing
    private let deviceActivityService: DeviceActivityServicing
    private let appGroupStore: AppGroupStore
    private let pauseRuleRepository: PauseRuleRepository
    private let pauseEventRepository: PauseEventRepository
    private let shieldPolicyResolver: ShieldPolicyResolver
    private let liveActivityController: PauseAllowanceLiveActivityControlling

    private(set) var state: PauseEngineState = .idle

    init(
        shieldService: ShieldServicing,
        deviceActivityService: DeviceActivityServicing,
        appGroupStore: AppGroupStore,
        pauseRuleRepository: PauseRuleRepository,
        pauseEventRepository: PauseEventRepository,
        shieldPolicyResolver: ShieldPolicyResolver = ShieldPolicyResolver(),
        liveActivityController: PauseAllowanceLiveActivityControlling = PauseAllowanceLiveActivityController()
    ) {
        self.liveActivityController = liveActivityController
        self.shieldService = shieldService
        self.deviceActivityService = deviceActivityService
        self.appGroupStore = appGroupStore
        self.pauseRuleRepository = pauseRuleRepository
        self.pauseEventRepository = pauseEventRepository
        self.shieldPolicyResolver = shieldPolicyResolver
    }

    func restore(from runtimeState: RuntimeState) async {
        if let allowance = runtimeState.activePauseAllowance, !allowance.isExpired {
            state = .temporarilyAllowed(allowance)
        } else if let allowance = runtimeState.activePauseAllowance, allowance.isExpired {
            state = .relocking(allowance.context)
            await relock(allowance.context)
        } else {
            state = .idle
        }
    }

    /// Recomputes the shield from whatever is stored right now and applies it.
    ///
    /// Nothing did this for pause rules: the shield was only ever recomputed when a
    /// routine started or stopped, or when an allowance was granted or relocked. So a
    /// newly created Pause never actually shielded its app, and the flow it describes
    /// could never be triggered. Call after any change to the rules, and on launch.
    func refreshShields() async {
        do {
            let runtime = try appGroupStore.loadRuntimeState()
            let pauseRules = await pauseRuleRepository.rules()
            let effectivePolicy = shieldPolicyResolver.resolve(
                activeRoutine: runtime.activeRoutine,
                activeBreak: runtime.activeBreak,
                activePauseAllowance: runtime.livePauseAllowance,
                pauseRules: pauseRules
            )

            if effectivePolicy.blocksNothing {
                try await shieldService.remove(runtime.shieldPolicy)
            } else {
                try await shieldService.apply(effectivePolicy)
            }
            try appGroupStore.updateRuntimeState { state in
                state.shieldPolicy = effectivePolicy
            }
            print("Refreshed shields rules=\(pauseRules.count) blockedApps=\(effectivePolicy.blockedApplications.count)")
        } catch {
            print("Refreshing shields failed: \(error.localizedDescription)")
        }
    }

    func request(_ context: PauseContext) async {
        state = .requested(context)
        do {
            try appGroupStore.updateRuntimeState { runtime in
                runtime.pendingPause = PendingPauseContext(
                    context: context,
                    expiresAt: Date().addingTimeInterval(10 * 60),
                    idempotencyKey: context.id.uuidString
                )
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func beginThinking(_ context: PauseContext) {
        let remaining = context.steps.compactMap { step -> Int? in
            guard case .countdown(let configuration) = step else { return nil }
            return Int(configuration.duration)
        }.first ?? 0
        state = .thinking(context, remainingSeconds: remaining)
    }

    func updateCountdown(context: PauseContext, remainingSeconds: Int) {
        state = remainingSeconds > 0
            ? .thinking(context, remainingSeconds: remainingSeconds)
            : .decision(context)
    }

    func allowTemporarily(_ context: PauseContext, intention: String?) async {
        let now = Date()
        let allowance = ActivePauseAllowance(
            context: context,
            startedAt: now,
            expiresAt: now.addingTimeInterval(context.allowanceDuration)
        )

        do {
            let runtime = try appGroupStore.loadRuntimeState()
            let pauseRules = await pauseRuleRepository.rules()
            let effectivePolicy = shieldPolicyResolver.resolve(
                activeRoutine: runtime.activeRoutine,
                activeBreak: runtime.activeBreak,
                activePauseAllowance: allowance,
                pauseRules: pauseRules
            )
            try appGroupStore.updateRuntimeState { runtime in
                runtime.pendingPause = nil
                // The shield action queues an event alongside the pending pause; leaving
                // it behind re-presented this same flow on the next foreground.
                runtime.pendingEvents.removeAll { $0.matchesPauseRequest(for: context.pauseRuleID) }
                runtime.activePauseAllowance = allowance
                runtime.shieldPolicy = effectivePolicy
            }
            // Lift the shield first. Relock scheduling used to run before this and its
            // failure aborted the whole unlock: DeviceActivitySchedule requires at least
            // a 15 minute interval, so any shorter allowance (the default is 5) threw and
            // the app stayed locked. The allowance expiry is also enforced on foreground,
            // so a missing schedule degrades rather than breaks.
            if effectivePolicy.blocksNothing {
                try await shieldService.remove(runtime.shieldPolicy)
            } else {
                try await shieldService.apply(effectivePolicy)
            }

            do {
                try await deviceActivityService.schedulePauseRelock(allowance)
            } catch {
                print("Pause relock scheduling failed (allowance \(Int(context.allowanceDuration / 60))m): \(error.localizedDescription)")
            }
            await pauseEventRepository.save(
                PauseEvent(
                    pauseRuleID: context.pauseRuleID,
                    application: AppIdentity(
                        id: context.appID,
                        displayName: context.displayName
                    ),
                    triggeredAt: context.requestedAt,
                    completedAt: now,
                    intention: intention,
                    decision: .continued,
                    allowanceDuration: context.allowanceDuration,
                    actualUsageDuration: nil
                )
            )
            clearPauseNotification(for: context.pauseRuleID)
            await liveActivityController.start(for: allowance)
            state = .temporarilyAllowed(allowance)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func cancel(_ context: PauseContext, intention: String?) async {
        do {
            try appGroupStore.updateRuntimeState { runtime in
                runtime.pendingPause = nil
                runtime.pendingEvents.removeAll { $0.matchesPauseRequest(for: context.pauseRuleID) }
            }
            await pauseEventRepository.save(
                PauseEvent(
                    pauseRuleID: context.pauseRuleID,
                    application: AppIdentity(
                        id: context.appID,
                        displayName: context.displayName
                    ),
                    triggeredAt: context.requestedAt,
                    completedAt: Date(),
                    intention: intention,
                    decision: .abandoned,
                    allowanceDuration: nil,
                    actualUsageDuration: nil
                )
            )
            clearPauseNotification(for: context.pauseRuleID)
            state = .cancelled(context)
            state = .locked(context)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Pulls the "Open ... mindfully" notification the shield action posted.
    ///
    /// It stays in Notification Centre otherwise, and tapping it later re-opens a pause
    /// that has already been answered.
    private func clearPauseNotification(for pauseRuleID: UUID) {
        let identifier = "pause-request-\(pauseRuleID.uuidString)"
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    func relock(_ context: PauseContext) async {
        state = .relocking(context)

        do {
            let runtime = try appGroupStore.loadRuntimeState()
            let pauseRules = await pauseRuleRepository.rules()
            let effectivePolicy = shieldPolicyResolver.resolve(
                activeRoutine: runtime.activeRoutine,
                activeBreak: runtime.activeBreak,
                activePauseAllowance: nil,
                pauseRules: pauseRules
            )
            if effectivePolicy.blocksNothing {
                try await shieldService.remove(runtime.shieldPolicy)
            } else {
                try await shieldService.apply(effectivePolicy)
            }
            try appGroupStore.updateRuntimeState { runtime in
                runtime.activePauseAllowance = nil
                runtime.pendingPause = nil
                runtime.pendingEvents.removeAll { $0.matchesPauseRequest(for: context.pauseRuleID) }
                runtime.shieldPolicy = effectivePolicy
            }
            clearPauseNotification(for: context.pauseRuleID)
            await liveActivityController.end()
            state = .locked(context)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
