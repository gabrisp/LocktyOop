import Foundation
import Combine
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

final class PauseEngine: ObservableObject {
    private let shieldService: ShieldServicing
    private let deviceActivityService: DeviceActivityServicing
    private let appGroupStore: AppGroupStore
    private let pauseRuleRepository: PauseRuleRepository
    private let pauseEventRepository: PauseEventRepository
    private let shieldPolicyResolver: ShieldPolicyResolver
    private let liveActivityController: PauseAllowanceLiveActivityControlling

    @Published private(set) var state: PauseEngineState = .idle
    /// Relocks on the allowance's own clock while the app is running.
    ///
    /// The monitor extension's usage threshold only fires once the granted minutes have
    /// actually been spent in the released apps, so an allowance the user let run out
    /// with Lockty open never ended by itself: the countdown reached zero and everything
    /// stayed unlocked until something else recomputed the shields.
    private var expiryTask: Task<Void, Never>?

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
            scheduleExpiryRelock(for: allowance)
        } else if let allowance = runtimeState.activePauseAllowance, allowance.isExpired {
            state = .relocking(allowance.context)
            await relock(allowance.context)
        } else {
            // Nothing is running, so nothing should still be counting down on the Lock
            // Screen. The monitor extension clears the allowance when it relocks in the
            // background, and this branch is where the app arrives afterwards -- it used
            // to fall straight to idle and leave a Live Activity nobody could end, since
            // relock() is the only thing that ends one and it is never reached from here.
            Task { await liveActivityController.end() }
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
            let shieldRules = appGroupStore.loadShieldRules()
            let effectivePolicy = shieldPolicyResolver.resolve(
                activeRoutines: runtime.activeRoutines,
                activeBreaks: runtime.activeBreaks,
                activePauseAllowance: runtime.livePauseAllowance,
                pauseRules: pauseRules,
                rules: shieldRules.rules,
                ruleEnforcement: shieldRules.enforcement,
                alwaysAllowedApplications: appGroupStore.loadAlwaysAllowedApplications()
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
            let shieldRules = appGroupStore.loadShieldRules()
            let effectivePolicy = shieldPolicyResolver.resolve(
                activeRoutines: runtime.activeRoutines,
                activeBreaks: runtime.activeBreaks,
                activePauseAllowance: allowance,
                pauseRules: pauseRules,
                rules: shieldRules.rules,
                ruleEnforcement: shieldRules.enforcement,
                alwaysAllowedApplications: appGroupStore.loadAlwaysAllowedApplications()
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

            // Charged here and not in the shield action: the button that asked for this
            // unlock is not the unlock. A flow the user started and then backed out of
            // must not cost them one of the day's opens.
            if let limitRuleID = context.limitRuleID {
                RuleShieldLookup(appGroupStore: appGroupStore).chargePass(ruleID: limitRuleID)
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
            scheduleExpiryRelock(for: allowance)
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

    /// Waits out the allowance and relocks on the second it expires.
    ///
    /// The sleep is checked rather than trusted. It is suspended along with the app, so
    /// it can come back late -- which is what left the countdown sitting at 0:00 for a
    /// while before anything happened -- and it can also come back a moment early. Both
    /// end in the same place: keep looking until the allowance has actually run out.
    private func scheduleExpiryRelock(for allowance: ActivePauseAllowance) {
        expiryTask?.cancel()
        guard allowance.expiresAt.timeIntervalSinceNow > 0 else { return }
        scheduleExpiryNotification(for: allowance)

        expiryTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let remaining = allowance.expiresAt.timeIntervalSinceNow
                guard remaining > 0 else { break }
                try? await Task.sleep(for: .seconds(min(remaining, 1)))
            }

            guard !Task.isCancelled, let self else { return }
            // Re-read rather than trusting the captured allowance: it may already have
            // been relocked by the monitor extension, or replaced by a newer one.
            guard let stored = try? self.appGroupStore.loadRuntimeState().activePauseAllowance,
                  stored.id == allowance.id
            else { return }
            await self.relock(allowance.context)
        }
    }

    /// Fires the moment the allowance runs out.
    ///
    /// The only way to say so when the app is not running: nothing can relock in the
    /// background on the wall clock -- DeviceActivity refuses any window under fifteen
    /// minutes -- so the phone is told, and opening Lockty from it relocks straight away.
    private func scheduleExpiryNotification(for allowance: ActivePauseAllowance) {
        let remaining = allowance.expiresAt.timeIntervalSinceNow
        guard remaining > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Break is over"
        content.body = "\(allowance.context.displayName) is blocked again."
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(
            identifier: Self.expiryNotificationIdentifier(for: allowance.id),
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: remaining, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// The expiry warning has nothing to warn about once the app is locked again.
    private func clearExpiryNotifications() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let identifiers = requests
                .map(\.identifier)
                .filter { $0.hasPrefix("pause-expiry-") }
            guard !identifiers.isEmpty else { return }
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }

    private static func expiryNotificationIdentifier(for allowanceID: UUID) -> String {
        "pause-expiry-\(allowanceID.uuidString)"
    }

    func relock(_ context: PauseContext) async {
        expiryTask?.cancel()
        expiryTask = nil
        state = .relocking(context)

        do {
            let runtime = try appGroupStore.loadRuntimeState()
            let pauseRules = await pauseRuleRepository.rules()
            let shieldRules = appGroupStore.loadShieldRules()
            let effectivePolicy = shieldPolicyResolver.resolve(
                activeRoutines: runtime.activeRoutines,
                activeBreaks: runtime.activeBreaks,
                activePauseAllowance: nil,
                pauseRules: pauseRules,
                rules: shieldRules.rules,
                ruleEnforcement: shieldRules.enforcement,
                alwaysAllowedApplications: appGroupStore.loadAlwaysAllowedApplications()
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
            clearExpiryNotifications()
            await liveActivityController.end()
            state = .locked(context)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
