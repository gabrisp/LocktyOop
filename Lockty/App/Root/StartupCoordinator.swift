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

            let presentedPause = runtimeState.pendingPause.flatMap { $0.isValid ? $0 : nil }
            if let presentedPause {
                router.presentFullScreen(.pause(presentedPause.context))
            }

            consumePendingEvents(from: runtimeState, pauseAlreadyPresented: presentedPause != nil)
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

        let presentedPause = runtimeState.pendingPause.flatMap { $0.isValid ? $0 : nil }
        if let presentedPause {
            router.presentFullScreen(.pause(presentedPause.context))
        }

        consumePendingEvents(from: runtimeState, pauseAlreadyPresented: presentedPause != nil)
    }

    private func reconcileRuntimeState(_ runtimeState: RuntimeState) async throws {
        if !runtimeState.shieldPolicy.blocksNothing || runtimeState.recoveryFlags.contains(.shieldRestoreNeeded) {
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

    /// Handles the first pending event and clears the queue.
    ///
    /// It used to only read the queue: nothing ever removed an event, so the pause the
    /// shield wrote came back on every single foreground for the full ten minutes it
    /// stayed valid -- and it was presented twice per foreground, once from pendingPause
    /// and again from here, which left the flow half-presented and unable to finish.
    private func consumePendingEvents(from runtimeState: RuntimeState, pauseAlreadyPresented: Bool) {
        let pendingEvents = runtimeState.pendingEvents.filter { !$0.isExpired }
        defer {
            try? appGroupStore.updateRuntimeState { state in
                state.pendingEvents = []
            }
        }

        guard let event = pendingEvents.first else { return }

        switch event.payload {
        case .pauseRequested(let context):
            guard !pauseAlreadyPresented else { return }
            router.presentFullScreen(.pause(context))
        case .routineStartRequested:
            break
        case .settingsRequested:
            router.presentSheet(.settings)
        }
    }
}
