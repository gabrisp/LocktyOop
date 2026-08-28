import Foundation
import Observation

@Observable
final class StartupCoordinator {
    private let session: AppSession
    private let router: AppRouter
    private let appGroupStore: AppGroupStore
    private let pauseEngine: PauseEngine
    private let routineEngine: RoutineEngine
    private let shieldService: ShieldServicing
    private var hasStarted = false

    init(
        session: AppSession,
        router: AppRouter,
        appGroupStore: AppGroupStore,
        pauseEngine: PauseEngine,
        routineEngine: RoutineEngine,
        shieldService: ShieldServicing
    ) {
        self.session = session
        self.router = router
        self.appGroupStore = appGroupStore
        self.pauseEngine = pauseEngine
        self.routineEngine = routineEngine
        self.shieldService = shieldService
    }

    func startIfNeeded() async {
        guard !hasStarted else { return }
        hasStarted = true

        do {
            let runtimeState = try appGroupStore.loadRuntimeState()
            await routineEngine.restore(from: runtimeState)
            await pauseEngine.restore(from: runtimeState)
            try await reconcileRuntimeState(runtimeState)

            session.finishStartup(requiresOnboarding: !session.hasCompletedOnboarding)

            if let pendingPause = runtimeState.pendingPause, pendingPause.isValid {
                router.presentFullScreen(.pause(pendingPause.context))
            }

            consumePendingEvents(from: runtimeState)
        } catch {
            session.recordStartupError(error.localizedDescription)
            appGroupStore.resetRuntimeStateToSafeDefault()
            session.finishStartup(requiresOnboarding: !session.hasCompletedOnboarding)
        }
    }

    /// Re-checks for a pause requested while the app was backgrounded (the shield's
    /// secondary button writes one, then a notification brings the user back here).
    /// startIfNeeded() is one-shot, so it can't cover this.
    func handleForeground() async {
        guard hasStarted else {
            await startIfNeeded()
            return
        }

        guard let runtimeState = try? appGroupStore.loadRuntimeState() else { return }
        await pauseEngine.restore(from: runtimeState)

        if let pendingPause = runtimeState.pendingPause, pendingPause.isValid {
            router.presentFullScreen(.pause(pendingPause.context))
        }

        consumePendingEvents(from: runtimeState)
    }

    private func reconcileRuntimeState(_ runtimeState: RuntimeState) async throws {
        if runtimeState.shieldPolicy != .empty || runtimeState.recoveryFlags.contains(.shieldRestoreNeeded) {
            try await shieldService.restoreFromRuntimeState()
        }

        if runtimeState.recoveryFlags.contains(.expiredPauseNeedsRelock),
           let allowance = runtimeState.activePauseAllowance {
            await pauseEngine.relock(allowance.context)
        }

        if runtimeState.recoveryFlags.contains(.expiredBreakNeedsFinalization),
           runtimeState.activeBreak != nil {
            await routineEngine.endBreakIfNeeded(reason: .breakExpired)
        }

        let filteredEvents = runtimeState.pendingEvents.filter { !$0.isExpired }
        try appGroupStore.updateRuntimeState { state in
            state.pendingEvents = filteredEvents
            state.recoveryFlags = []
        }
    }

    private func consumePendingEvents(from runtimeState: RuntimeState) {
        let pendingEvents = runtimeState.pendingEvents.filter { !$0.isExpired }
        guard let event = pendingEvents.first else { return }

        switch event.payload {
        case .pauseRequested(let context):
            router.presentFullScreen(.pause(context))
        case .routineStartRequested:
            break
        case .settingsRequested:
            router.push(.settings)
        }
    }
}
