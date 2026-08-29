import Foundation
import Combine

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

    func start(_ routine: Routine, trigger: RoutineTrigger = .manual) async {
        if case .active(let current) = state {
            if current.routineID == routine.id {
                return
            }

            state = .failed("Another routine is already active.")
            return
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
            let effectivePolicy = shieldPolicyResolver.resolve(
                activeRoutine: activeRoutine,
                activeBreak: nil,
                activePauseAllowance: try appGroupStore.loadRuntimeState().livePauseAllowance,
                pauseRules: pauseRules
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
        } catch {
            state = .failed(error.localizedDescription)
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
        let residualPolicy = shieldPolicyResolver.resolve(
            activeRoutine: nil,
            activeBreak: nil,
            // Not the live allowance: an allowance only exists to let an app through a
            // routine's shield, and the routine is going.
            activePauseAllowance: nil,
            pauseRules: pauseRules
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
        let decision = strictModePolicy.decision(for: .startBreak, activeRoutine: activeRoutine)
        guard decision.isAllowed else {
            state = .failed(decision.reason ?? "Break is not allowed.")
            state = .active(activeRoutine)
            return
        }

        guard activeRoutine.breakPolicySnapshot.maximumBreaks > 0 else {
            state = .failed("This routine does not allow breaks.")
            state = .active(activeRoutine)
            return
        }

        guard activeRoutine.breakPolicySnapshot.allowedTriggers.contains(trigger) else {
            state = .failed("This break trigger is not allowed for the active routine.")
            state = .active(activeRoutine)
            return
        }

        do {
            let existing = try await executionRepository.execution(id: activeRoutine.id)
            let breakHistory = existing?.breakHistory ?? []
            guard breakHistory.count < activeRoutine.breakPolicySnapshot.maximumBreaks else {
                state = .failed("Break limit reached.")
                state = .active(activeRoutine)
                return
            }

            if let lastBreak = breakHistory.last, let endedAt = lastBreak.endedAt {
                let elapsed = Date().timeIntervalSince(endedAt)
                guard elapsed >= activeRoutine.breakPolicySnapshot.minimumInterval else {
                    state = .failed("The minimum break interval has not passed yet.")
                    state = .active(activeRoutine)
                    return
                }
            }

            let activeBreak = ActiveBreak(
                routineID: activeRoutine.routineID,
                startedAt: Date(),
                endsAt: Date().addingTimeInterval(activeRoutine.breakPolicySnapshot.maximumDuration),
                trigger: trigger
            )

            let pauseRules = await pauseRuleRepository.rules()
            let effectivePolicy = shieldPolicyResolver.resolve(
                activeRoutine: activeRoutine,
                activeBreak: activeBreak,
                activePauseAllowance: try appGroupStore.loadRuntimeState().livePauseAllowance,
                pauseRules: pauseRules
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
            let effectivePolicy = shieldPolicyResolver.resolve(
                activeRoutine: activeRoutine,
                activeBreak: nil,
                activePauseAllowance: try appGroupStore.loadRuntimeState().livePauseAllowance,
                pauseRules: pauseRules
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
