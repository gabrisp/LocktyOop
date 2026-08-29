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

    func stop() async {
        let activeRoutine: ActiveRoutine

        switch state {
        case .active(let routine):
            activeRoutine = routine
        case .onBreak(let routine, let breakState):
            activeRoutine = routine
            _ = breakState
        default:
            return
        }

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

        do {
            try await finalizeExecution(
                id: activeRoutine.id,
                endedAt: Date(),
                completionReason: .manualStop
            )
            let pauseRules = await pauseRuleRepository.rules()
            let effectivePolicy = shieldPolicyResolver.resolve(
                activeRoutine: nil,
                activeBreak: nil,
                activePauseAllowance: try appGroupStore.loadRuntimeState().livePauseAllowance,
                pauseRules: pauseRules
            )
            try appGroupStore.updateRuntimeState { runtime in
                runtime.activeRoutine = nil
                runtime.activeBreak = nil
                runtime.shieldPolicy = effectivePolicy
            }
            if effectivePolicy.blocksNothing {
                try await shieldService.remove(activeRoutine.shieldPolicy)
            } else {
                try await shieldService.apply(effectivePolicy)
            }
            state = .completed(activeRoutine.routineID)
        } catch {
            state = .failed(error.localizedDescription)
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
            state = .active(activeRoutine)

            if reason == .breakExpired, activeRoutine.modeSnapshot == .strict {
                await stop()
            }
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
