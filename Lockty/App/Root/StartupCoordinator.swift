import Combine
import Foundation
import SwiftUI
import UserNotifications

final class StartupCoordinator: ObservableObject {
    private let session: AppSession
    private let router: AppRouter
    private let appGroupStore: AppGroupStore
    private let pauseEngine: PauseEngine
    private let frictionRepository: FrictionRepository
    private let notificationService: NotificationServicing
    private let routineEngine: RoutineEngine
    private let shieldService: ShieldServicing
    @Published private var hasStarted = false

    init(
        session: AppSession,
        router: AppRouter,
        appGroupStore: AppGroupStore,
        pauseEngine: PauseEngine,
        frictionRepository: FrictionRepository,
        notificationService: NotificationServicing,
        routineEngine: RoutineEngine,
        shieldService: ShieldServicing
    ) {
        self.session = session
        self.router = router
        self.appGroupStore = appGroupStore
        self.pauseEngine = pauseEngine
        self.frictionRepository = frictionRepository
        self.notificationService = notificationService
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
            // The stored policy can be out of date with the stored rules -- a Pause
            // created while nothing else recomputed the shield left no policy at all.
            await frictionRepository.seedDefaultFrictionIfNeeded()
            await pauseEngine.refreshShields()

            session.finishStartup(requiresOnboarding: !session.hasCompletedOnboarding)
            await requestNotificationsIfNeeded()

            let presentedPause = runtimeState.pendingPause.flatMap { $0.isValid ? $0 : nil }
            present(presentedPause)

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

        // Surfaced as a card on Today rather than presented: a cover thrown up over
        // whatever the user was doing is also what made it loop, since pendingPause
        // survives until the flow is actually answered.
        let presentedPause = runtimeState.pendingPause.flatMap { $0.isValid ? $0 : nil }
        present(presentedPause)

        consumePendingEvents(from: runtimeState, pauseAlreadyPresented: presentedPause != nil)
    }

    /// Asks for notifications on the first launch that gets this far.
    ///
    /// It was only ever asked for from the system-access screen, which nothing sends the
    /// user to -- so the permission was usually never granted and the shield's unlock
    /// notification, the only way back into Lockty from a blocked app, was dropped by the
    /// system without a word.
    private func requestNotificationsIfNeeded() async {
        guard await notificationService.refreshAuthorization() == .notDetermined else { return }
        _ = await notificationService.requestAuthorization()
    }

    /// Puts the unlock request on screen, on the screen that shows it.
    ///
    /// The shield opens Lockty straight into whatever tab it was left on, and the card
    /// lives on Today -- so arriving from a blocked app could land on Routines with the
    /// request nowhere in sight.
    private func present(_ presentedPause: PendingPauseContext?) {
        guard let presentedPause else {
            router.pendingUnlock = nil
            return
        }

        withAnimation(.smooth(duration: 0.3)) {
            router.select(.today)
            router.pendingUnlock = presentedPause.context
        }
        clearUnlockNotification(for: presentedPause.context.pauseRuleID)
    }

    /// The shield posts a notification alongside opening the app, because it cannot tell
    /// whether the open landed. Once the request is on screen the notification has done
    /// its job either way.
    private func clearUnlockNotification(for pauseRuleID: UUID) {
        let identifier = "pause-request-\(pauseRuleID.uuidString)"
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
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
            withAnimation(.smooth(duration: 0.3)) {
                router.select(.today)
                router.pendingUnlock = context
            }
        case .routineStartRequested:
            break
        case .settingsRequested:
            router.presentSheet(.settings)
        }
    }
}
