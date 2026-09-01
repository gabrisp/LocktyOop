import Foundation
import Combine

/// What came of asking the engine to start a routine.
///
/// Returned rather than left behind in `state`, because the two answers pull in opposite
/// directions: the caller needs the reason it was refused, and the engine needs to go on
/// reporting the routine that is actually running. Parking a `.failed` in `state` to
/// carry the message made `activeRoutine()` nil for everything else in the app.
enum RoutineStartOutcome: Equatable {
    case started
    /// Already the running routine. Nothing happened, and nothing needed to.
    case alreadyRunning
    /// Something else is running, so this one was refused.
    case blocked(String)
    case failed(String)

    var errorMessage: String? {
        switch self {
        case .started, .alreadyRunning:
            nil
        case .blocked(let message), .failed(let message):
            message
        }
    }
}

enum RoutineEngineState: Equatable {
    case inactive
    case starting(UUID)
    case active(ActiveRoutine)
    case onBreak(ActiveRoutine, ActiveBreak)
    case ending(UUID)
    case completed(UUID)
    case failed(String)
}

final class RoutineEngine: ObservableObject {
    private let shieldService: ShieldServicing
    private let deviceActivityService: DeviceActivityServicing
    private let alarmService: AlarmServicing
    private let appGroupStore: AppGroupStore
    private let pauseRuleRepository: PauseRuleRepository
    private let executionRepository: RoutineExecutionRepository
    private let shieldPolicyResolver: ShieldPolicyResolver
    private let strictModePolicy = StrictModePolicy()

    @Published private(set) var state: RoutineEngineState = .inactive

    init(
        shieldService: ShieldServicing,
        deviceActivityService: DeviceActivityServicing,
        alarmService: AlarmServicing,
        appGroupStore: AppGroupStore,
        pauseRuleRepository: PauseRuleRepository,
        executionRepository: RoutineExecutionRepository,
        shieldPolicyResolver: ShieldPolicyResolver = ShieldPolicyResolver()
    ) {
        self.shieldService = shieldService
        self.deviceActivityService = deviceActivityService
        self.alarmService = alarmService
        self.appGroupStore = appGroupStore
        self.pauseRuleRepository = pauseRuleRepository
        self.executionRepository = executionRepository
        self.shieldPolicyResolver = shieldPolicyResolver
    }

    func restore(from runtimeState: RuntimeState) async {
        if let activeRoutine = runtimeState.activeRoutine, let activeBreak = runtimeState.activeBreak {
            if activeBreak.endsAt <= Date() {
                state = .onBreak(activeRoutine, activeBreak)
                await endBreakIfNeeded(reason: .breakExpired)
                return
            }
            state = .onBreak(activeRoutine, activeBreak)
        } else if let activeRoutine = runtimeState.activeRoutine {
            state = .active(activeRoutine)
        } else {
            state = .inactive
        }
    }

    /// Starts a routine, unless something is already running.
    ///
    /// Every way of already running is refused here, not just `.active`. A routine on a
    /// break is still the running routine, and `.starting` is one that is halfway
    /// through this same function -- both used to fall straight through and overwrite
    /// `runtime.activeRoutine`, which left the first routine's shields applied with
    /// nothing pointing at them any more.
    ///
    /// The App Group is consulted too. A routine the monitor extension started while the
    /// app was not running is in the runtime state and *not* in this engine's `state`,
    /// so a manual start displaced it without ever noticing it was there.
    @discardableResult
    func start(_ routine: Routine, trigger: RoutineTrigger = .manual) async -> RoutineStartOutcome {
        let running: ActiveRoutine?
        switch state {
        case .active(let current), .onBreak(let current, _):
            running = current
        case .starting(let id):
            // Already on its way in from an earlier call to this function.
            guard id != routine.id else { return .alreadyRunning }
            running = (try? appGroupStore.loadRuntimeState())?.activeRoutine
        default:
            running = (try? appGroupStore.loadRuntimeState())?.activeRoutine
        }

        if let running {
            guard running.routineID != routine.id else {
                // Already the one running: make the engine agree with the runtime state
                // rather than reporting a failure for a routine that is up.
                if case .onBreak = state {} else { state = .active(running) }
                return .alreadyRunning
            }

            // The engine keeps reporting the routine that really is running. Only the
            // caller is told why this one was refused.
            state = .active(running)
            return .blocked("\(running.nameSnapshot) is already running. End it first.")
        }

        state = .starting(routine.id)
        let taskCompletions = routine.tasks
            .sorted { $0.order < $1.order }
            .map {
                RoutineTaskCompletion(
                    taskID: $0.id,
                    titleSnapshot: $0.title,
                    orderSnapshot: $0.order
                )
            }
        let activeRoutine = ActiveRoutine(
            routineID: routine.id,
            nameSnapshot: routine.name,
            iconSnapshot: routine.icon,
            modeSnapshot: routine.mode,
            startedAt: Date(),
            trigger: trigger,
            shieldPolicy: .routine(routine),
            breakPolicySnapshot: routine.breakPolicy,
            pausePolicySnapshot: routine.pausePolicy,
            taskCompletions: taskCompletions,
            allowsPauseDuringStrictMode: routine.allowsPauseDuringStrictMode
        )

        do {
            let pauseRules = await pauseRuleRepository.rules()
            let shieldRules = appGroupStore.loadShieldRules()
            let effectivePolicy = shieldPolicyResolver.resolve(
                activeRoutine: activeRoutine,
                activeBreak: nil,
                activePauseAllowance: try appGroupStore.loadRuntimeState().livePauseAllowance,
                pauseRules: pauseRules,
                rules: shieldRules.rules,
                ruleEnforcement: shieldRules.enforcement
            )
            try appGroupStore.updateRuntimeState { runtime in
                runtime.activeRoutine = activeRoutine
                runtime.shieldPolicy = effectivePolicy
            }
            try await shieldService.apply(effectivePolicy)
            try await executionRepository.save(
                RoutineExecution(
                    id: activeRoutine.id,
                    routineID: routine.id,
                    routineName: routine.name,
                    startedAt: activeRoutine.startedAt,
                    taskCompletions: activeRoutine.taskCompletions
                )
            )
            state = .active(activeRoutine)
            try? await alarmService.triggerRoutineStartAlarm(for: routine)
            return .started
        } catch {
            state = .failed(error.localizedDescription)
            return .failed(error.localizedDescription)
        }
    }

    /// Ends whatever is running and takes the whole session down with it.
    ///
    /// The routine is taken from the App Group when this engine's own state doesn't
    /// carry one: a routine started by the monitor extension, or a state left at .failed
    /// by some earlier operation, used to fall through to a silent return here -- the
    /// sheet closed, the routine read as over, and every app stayed shielded with nothing
    /// left on screen offering to unshield it. Stopping is now unconditional: even with
    /// no routine anywhere it still clears the restrictions, because the shields are what
    /// the user is actually asking to be rid of.
    func stop() async {
        let storedState = try? appGroupStore.loadRuntimeState()
        let activeRoutine: ActiveRoutine?

        switch state {
        case .active(let routine):
            activeRoutine = routine
        case .onBreak(let routine, _):
            activeRoutine = routine
        default:
            activeRoutine = storedState?.activeRoutine
        }

        if let activeRoutine {
            let decision = strictModePolicy.decision(
                for: .stopRoutine,
                activeRoutine: activeRoutine
            )
            guard decision.isAllowed else {
                state = .failed(decision.reason ?? "Stopping this routine is not allowed.")
                state = .active(activeRoutine)
                return
            }

            state = .ending(activeRoutine.routineID)
        }

        // Deliberately not one do/catch. Every step here used to be inside a single
        // throwing block, so the first failure aborted the rest: with a stale pause rule
        // stored, recomputing the shield threw .selectionNotConfigured before anything
        // had been cleared, and stopping left the phone exactly as it was. Each step now
        // fails on its own, and the two that matter -- the shields coming off and the
        // runtime being cleared -- run first and cannot be skipped.
        try? await shieldService.remove(storedState?.shieldPolicy ?? .empty)

        do {
            try appGroupStore.updateRuntimeState { runtime in
                runtime.activeRoutine = nil
                runtime.activeBreak = nil
                // Everything the routine was carrying goes with it: the allowance it
                // granted, the unlock the shield left waiting, the events queued behind
                // them. These outlived the routine and kept the pending-unlock card on
                // Today for a routine that had already ended.
                runtime.activePauseAllowance = nil
                runtime.pendingPause = nil
                runtime.pendingEvents = []
                runtime.recoveryFlags = []
                runtime.shieldPolicy = .empty
            }
        } catch {
            print("Clearing the runtime state on stop failed: \(error.localizedDescription)")
        }

        // Detached, and not awaited. Neither is needed for the routine to be over, and
        // both talk to daemons that can take their time answering -- awaiting them held
        // the button that started this.
        Task { [deviceActivityService] in
            await deviceActivityService.cancelPauseRelocks()
            await PauseAllowanceLiveActivityTermination.endAll()
        }

        // Anything a standalone Pause still blocks goes back on top of the cleared state.
        // Its failure is survivable in the right direction: nothing shielded.
        let pauseRules = await pauseRuleRepository.rules()
            let shieldRules = appGroupStore.loadShieldRules()
        let residualPolicy = shieldPolicyResolver.resolve(
            activeRoutine: nil,
            activeBreak: nil,
            // Not the live allowance: an allowance only exists to let an app through a
            // routine's shield, and the routine is going.
            activePauseAllowance: nil,
            pauseRules: pauseRules,
                rules: shieldRules.rules,
                ruleEnforcement: shieldRules.enforcement
        )
        if !residualPolicy.blocksNothing {
            do {
                try await shieldService.apply(residualPolicy)
            } catch {
                print("Re-applying pause rules after stopping failed: \(error.localizedDescription)")
            }
        }

        if let activeRoutine {
            do {
                try await finalizeExecution(
                    id: activeRoutine.id,
                    endedAt: Date(),
                    completionReason: .manualStop
                )
            } catch {
                // History, not state. A routine that could not be written to the log has
                // still stopped.
                print("Finalizing the execution log failed: \(error.localizedDescription)")
            }
            state = .completed(activeRoutine.routineID)
        } else {
            state = .inactive
        }
    }

    /// Toggles the task: tapping a completed item clears it again. The checklist is the
    /// only way to change these, so it has to work in both directions.
    func completeTask(_ taskID: UUID) async {
        guard case .active(var activeRoutine) = state else { return }
        guard let index = activeRoutine.taskCompletions.firstIndex(where: { $0.taskID == taskID }) else { return }
        activeRoutine.taskCompletions[index].completedAt =
            activeRoutine.taskCompletions[index].completedAt == nil ? Date() : nil

        do {
            try appGroupStore.updateRuntimeState { runtime in
                runtime.activeRoutine = activeRoutine
            }
            try await executionRepository.save(
                RoutineExecution(
                    id: activeRoutine.id,
                    routineID: activeRoutine.routineID,
                    routineName: activeRoutine.nameSnapshot,
                    startedAt: activeRoutine.startedAt,
                    taskCompletions: activeRoutine.taskCompletions
                )
            )
            state = .active(activeRoutine)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func startBreak(trigger: BreakTrigger) async {
        guard case .active(let activeRoutine) = state else { return }
        switch await breakAvailability(for: activeRoutine.routineID, trigger: trigger, requiresFriction: false) {
        case .available:
            break
        case .unavailable(let unavailable):
            state = .failed(unavailable.message)
            state = .active(activeRoutine)
            return
        }

        do {
            let existing = try await executionRepository.execution(id: activeRoutine.id)
            let activeBreak = ActiveBreak(
                routineID: activeRoutine.routineID,
                startedAt: Date(),
                endsAt: Date().addingTimeInterval(activeRoutine.breakPolicySnapshot.maximumDuration),
                trigger: trigger
            )

            let pauseRules = await pauseRuleRepository.rules()
            let shieldRules = appGroupStore.loadShieldRules()
            let effectivePolicy = shieldPolicyResolver.resolve(
                activeRoutine: activeRoutine,
                activeBreak: activeBreak,
                activePauseAllowance: try appGroupStore.loadRuntimeState().livePauseAllowance,
                pauseRules: pauseRules,
                rules: shieldRules.rules,
                ruleEnforcement: shieldRules.enforcement
            )

            try appGroupStore.updateRuntimeState { runtime in
                runtime.activeBreak = activeBreak
                runtime.shieldPolicy = effectivePolicy
            }
            try await deviceActivityService.scheduleBreakEnd(activeBreak)

            if effectivePolicy.blocksNothing {
                try await shieldService.remove(activeRoutine.shieldPolicy)
            } else {
                try await shieldService.apply(effectivePolicy)
            }

            var execution = existing ?? RoutineExecution(
                id: activeRoutine.id,
                routineID: activeRoutine.routineID,
                routineName: activeRoutine.nameSnapshot,
                startedAt: activeRoutine.startedAt,
                taskCompletions: activeRoutine.taskCompletions
            )
            execution.breakHistory.append(
                RoutineBreakRecord(
                    id: activeBreak.id,
                    startedAt: activeBreak.startedAt,
                    trigger: trigger
                )
            )
            try await executionRepository.save(execution)
            state = .onBreak(activeRoutine, activeBreak)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func breakAvailability(
        for routineID: UUID?,
        trigger: BreakTrigger,
        requiresFriction: Bool
    ) async -> BreakAvailability {
        guard let routineID,
              let activeRoutine = activeRoutine(),
              activeRoutine.routineID == routineID
        else {
            return .unavailable(
                BreakUnavailableState(
                    title: "Rule inactive",
                    message: "Esta rule ya no esta activa."
                )
            )
        }

        let strictDecision = strictModePolicy.decision(for: .startBreak, activeRoutine: activeRoutine)
        guard strictDecision.isAllowed else {
            return .unavailable(
                BreakUnavailableState(
                    title: "Strict mode",
                    message: strictDecision.reason ?? "Esta routine no permite breaks ahora."
                )
            )
        }

        let policy = activeRoutine.breakPolicySnapshot
        guard policy.maximumBreaks > 0 else {
            return .unavailable(
                BreakUnavailableState(
                    title: "Breaks disabled",
                    message: "Blocked means blocked."
                )
            )
        }

        guard policy.allowedTriggers.contains(trigger) else {
            return .unavailable(
                BreakUnavailableState(
                    title: "Break unavailable",
                    message: "Este trigger no esta permitido en esta rule."
                )
            )
        }

        if requiresFriction && !activeRoutine.pausePolicySnapshot.offersPause {
            return .unavailable(
                BreakUnavailableState(
                    title: "Friction required",
                    message: "Selecciona una friction dentro de Break."
                )
            )
        }

        do {
            let breakHistory = try await executionRepository.execution(id: activeRoutine.id)?.breakHistory ?? []
            guard breakHistory.count < policy.maximumBreaks else {
                return .unavailable(
                    BreakUnavailableState(
                        title: "Break limit reached",
                        message: "Has alcanzado el maximo de breaks."
                    )
                )
            }

            // A break's endedAt is only written by endBreakIfNeeded, which needs the app
            // to be running when the break expires. One that ran out in the background --
            // the monitor extension clears activeBreak and nothing writes the end -- left
            // a record with no endedAt at all, so `max()` was nil and the cooldown simply
            // never applied. The break's own duration says when it was over, so an
            // unfinished record falls back to that rather than being skipped.
            let lastEnd = breakHistory
                .map { $0.endedAt ?? $0.startedAt.addingTimeInterval(policy.maximumDuration) }
                .max()

            if let lastEnd {
                let retryAt = lastEnd.addingTimeInterval(policy.minimumInterval)
                guard Date() >= retryAt else {
                    return .unavailable(
                        BreakUnavailableState(
                            title: "Cooldown",
                            message: "Espera para volver a pedir otro break.",
                            retryAt: retryAt
                        )
                    )
                }
            }
        } catch {
            return .unavailable(
                BreakUnavailableState(
                    title: "Break unavailable",
                    message: error.localizedDescription
                )
            )
        }

        return .available
    }

    func endBreakIfNeeded(reason: RoutineCompletionReason = .naturalCompletion) async {
        guard case .onBreak(let activeRoutine, let activeBreak) = state else { return }

        do {
            var execution = try await executionRepository.execution(id: activeRoutine.id) ?? RoutineExecution(
                id: activeRoutine.id,
                routineID: activeRoutine.routineID,
                routineName: activeRoutine.nameSnapshot,
                startedAt: activeRoutine.startedAt,
                taskCompletions: activeRoutine.taskCompletions
            )
            if let index = execution.breakHistory.firstIndex(where: { $0.id == activeBreak.id }) {
                execution.breakHistory[index].endedAt = Date()
            }
            try await executionRepository.save(execution)

            let pauseRules = await pauseRuleRepository.rules()
            let shieldRules = appGroupStore.loadShieldRules()
            let effectivePolicy = shieldPolicyResolver.resolve(
                activeRoutine: activeRoutine,
                activeBreak: nil,
                activePauseAllowance: try appGroupStore.loadRuntimeState().livePauseAllowance,
                pauseRules: pauseRules,
                rules: shieldRules.rules,
                ruleEnforcement: shieldRules.enforcement
            )
            try appGroupStore.updateRuntimeState { runtime in
                runtime.activeBreak = nil
                runtime.shieldPolicy = effectivePolicy
            }
            try await shieldService.apply(effectivePolicy)
            print("Routine break ended routineID=\(activeRoutine.routineID.uuidString) restoring routine shields")
            state = .active(activeRoutine)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func activeRoutine() -> ActiveRoutine? {
        switch state {
        case .active(let routine), .onBreak(let routine, _):
            routine
        default:
            nil
        }
    }

    private func finalizeExecution(
        id: UUID,
        endedAt: Date,
        completionReason: RoutineCompletionReason
    ) async throws {
        var execution = try await executionRepository.execution(id: id) ?? RoutineExecution(
            id: id,
            routineID: id,
            routineName: activeRoutine()?.nameSnapshot ?? "Routine",
            startedAt: activeRoutine()?.startedAt ?? endedAt
        )
        execution.endedAt = endedAt
        execution.completionReason = completionReason
        execution.taskCompletions = activeRoutine()?.taskCompletions ?? execution.taskCompletions
        try await executionRepository.save(execution)
    }
}
