import Foundation
import Observation

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

    private(set) var state: PauseEngineState = .idle

    init(
        shieldService: ShieldServicing,
        deviceActivityService: DeviceActivityServicing,
        appGroupStore: AppGroupStore,
        pauseRuleRepository: PauseRuleRepository,
        pauseEventRepository: PauseEventRepository,
        shieldPolicyResolver: ShieldPolicyResolver = ShieldPolicyResolver()
    ) {
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
                runtime.activePauseAllowance = allowance
                runtime.shieldPolicy = effectivePolicy
            }
            try await deviceActivityService.schedulePauseRelock(allowance)
            if effectivePolicy == .empty {
                try await shieldService.remove(runtime.shieldPolicy)
            } else {
                try await shieldService.apply(effectivePolicy)
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
            state = .temporarilyAllowed(allowance)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func cancel(_ context: PauseContext, intention: String?) async {
        do {
            try appGroupStore.updateRuntimeState { runtime in
                runtime.pendingPause = nil
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
            state = .cancelled(context)
            state = .locked(context)
        } catch {
            state = .failed(error.localizedDescription)
        }
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
            if effectivePolicy == .empty {
                try await shieldService.remove(runtime.shieldPolicy)
            } else {
                try await shieldService.apply(effectivePolicy)
            }
            try appGroupStore.updateRuntimeState { runtime in
                runtime.activePauseAllowance = nil
                runtime.pendingPause = nil
                runtime.shieldPolicy = effectivePolicy
            }
            state = .locked(context)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
