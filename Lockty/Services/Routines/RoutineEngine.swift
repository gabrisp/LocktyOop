import Foundation
import Combine

/// What came of asking the engine to start a routine.
///
/// Returned rather than left behind in `state`, because the two answers pull in opposite
/// directions: the caller needs the reason it was refused, and the engine needs to go on
/// reporting the routines that are actually running. Parking a `.failed` in `state` to
/// carry the message made `activeRoutine()` nil for everything else in the app.
enum RoutineStartOutcome: Equatable {
    case started
    /// Already running. Nothing happened, and nothing needed to.
    case alreadyRunning
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

/// The engine's state as a single answer, for the screens that can only show one.
///
/// Derived from the routines actually running rather than being the storage itself --
/// see `activeRoutines`. It reports the primary one, so a view with room for a single
/// routine keeps showing the same one as others come and go.
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

    /// Everything running right now. Routines are allowed to overlap, so this is the
    /// engine's real state; `state` below is a view onto it.
    @Published private(set) var activeRoutines: [ActiveRoutine] = []
    /// The breaks in flight, at most one per routine and each naming its own.
    @Published private(set) var activeBreaks: [ActiveBreak] = []
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

    // MARK: - Reading what is running

    /// The routine to show where only one fits: the first to have started, so the answer
    /// doesn't reshuffle underneath the user as others begin and end.
    func activeRoutine() -> ActiveRoutine? {
        activeRoutines.min { $0.startedAt < $1.startedAt }
    }

    func activeRoutine(id: UUID) -> ActiveRoutine? {
        activeRoutines.first { $0.routineID == id }
    }

    func activeBreak(for routineID: UUID) -> ActiveBreak? {
        activeBreaks.first { $0.routineID == routineID }
    }

    func isRunning(_ routineID: UUID) -> Bool {
        activeRoutine(id: routineID) != nil
    }

    /// Every running routine that blocks this app.
    ///
    /// More than one can, and that is the whole reason this returns a list: an app two
    /// routines block is not free until both of them agree to let it out.
    func activeRoutines(blocking appID: AppIdentity.ID) -> [ActiveRoutine] {
        activeRoutines.filter { $0.shieldPolicy.blockedApplications.contains(appID) }
    }

    private func refreshDerivedState() {
        guard let primary = activeRoutine() else {
            state = .inactive
            return
        }

        if let running = activeBreak(for: primary.routineID) {
            state = .onBreak(primary, running)
        } else {
            state = .active(primary)
        }
    }

    // MARK: - Lifecycle

    func restore(from runtimeState: RuntimeState) async {
        activeRoutines = runtimeState.activeRoutines
        activeBreaks = runtimeState.activeBreaks
        refreshDerivedState()

        // Any break whose clock ran out while the app was away is closed here, one by
        // one: they belong to different routines and finishing one must not skip another.
        for expired in activeBreaks.filter({ $0.endsAt <= Date() }) {
            await endBreak(routineID: expired.routineID, reason: .breakExpired)
        }
    }

    /// Starts a routine alongside whatever else is running.
    ///
    /// Overlapping routines are the point: two schedules covering the same hours both
    /// apply, and the shield is the union of what they block. Only starting the *same*
    /// routine twice is refused, because that is not a second routine, it is a repeat.
    @discardableResult
    func start(_ routine: Routine, trigger: RoutineTrigger = .manual) async -> RoutineStartOutcome {
        // The App Group is consulted, not just this engine: a routine the monitor
        // extension started while the app was not running is only in the runtime state,
        // and starting it again here would give it two entries and two executions.
        let stored = (try? appGroupStore.loadRuntimeState())?.activeRoutines ?? []
        if let alreadyRunning = (activeRoutines + stored).first(where: { $0.routineID == routine.id }) {
            if !activeRoutines.contains(where: { $0.routineID == routine.id }) {
                activeRoutines.append(alreadyRunning)
                refreshDerivedState()
            }
            return .alreadyRunning
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

        activeRoutines.append(activeRoutine)
        refreshDerivedState()

        do {
            try await applyShields()
            try await executionRepository.save(
                RoutineExecution(
                    id: activeRoutine.id,
                    routineID: routine.id,
                    routineName: routine.name,
                    startedAt: activeRoutine.startedAt,
                    taskCompletions: activeRoutine.taskCompletions
                )
            )
            try? await alarmService.triggerRoutineStartAlarm(for: routine)
            return .started
        } catch {
            // Rolled back rather than left half-started: a routine whose shields never
            // went up is not running, and leaving it in the list would have it counted
            // by everything that reads them.
            activeRoutines.removeAll { $0.routineID == routine.id }
            refreshDerivedState()
            state = .failed(error.localizedDescription)
            return .failed(error.localizedDescription)
        }
    }

    /// Ends one routine, leaving the others running.
    ///
    /// The shield is recomputed from what is left rather than being torn down: the apps
    /// this routine was holding come free, and any that another routine also blocks stay
    /// exactly where they are, because that routine never agreed to release them.
    ///
    /// Passing nil ends everything, which is what a user asking to be rid of the shields
    /// altogether means.
    func stop(routineID: UUID? = nil) async {
        await synchronizeWithStoredState()

        let targets: [ActiveRoutine]
        if let routineID {
            guard let target = activeRoutine(id: routineID) else {
                // Nothing here by that name, but the shields may still be up from a state
                // this engine never saw. Recomputing is the safe direction.
                try? await applyShields()
                return
            }
            targets = [target]
        } else {
            targets = activeRoutines
        }

        for target in targets {
            let decision = strictModePolicy.decision(for: .stopRoutine, activeRoutine: target)
            guard decision.isAllowed else {
                state = .failed(decision.reason ?? "Stopping this routine is not allowed.")
                refreshDerivedState()
                return
            }
        }

        let stoppedIDs = Set(targets.map(\.routineID))
        if let first = targets.first {
            state = .ending(first.routineID)
        }

        activeRoutines.removeAll { stoppedIDs.contains($0.routineID) }
        activeBreaks.removeAll { stoppedIDs.contains($0.routineID) }

        // Deliberately not one do/catch. Every step here used to be inside a single
        // throwing block, so the first failure aborted the rest: with a stale pause rule
        // stored, recomputing the shield threw before anything had been cleared, and
        // stopping left the phone exactly as it was.
        do {
            try await applyShields(clearPending: true)
        } catch {
            print("Recomputing the shield after stopping failed: \(error.localizedDescription)")
        }

        // Detached, and not awaited. Neither is needed for the routine to be over, and
        // both talk to daemons that can take their time answering -- awaiting them held
        // the button that started this.
        //
        // Only once nothing is left running: an allowance belongs to a routine, and
        // cancelling every relock because one of three routines ended would leave apps
        // the other two still hold shut without anything scheduled to re-lock them.
        if activeRoutines.isEmpty {
            Task { [deviceActivityService] in
                await deviceActivityService.cancelPauseRelocks()
                await PauseAllowanceLiveActivityTermination.endAll()
            }
        }

        for target in targets {
            do {
                try await finalizeExecution(
                    activeRoutine: target,
                    endedAt: Date(),
                    completionReason: .manualStop
                )
            } catch {
                // History, not state. A routine that could not be written to the log has
                // still stopped.
                print("Finalizing the execution log failed: \(error.localizedDescription)")
            }
        }

        if let last = targets.last {
            state = .completed(last.routineID)
        }
        refreshDerivedState()
    }

    /// Toggles the task: tapping a completed item clears it again. The checklist is the
    /// only way to change these, so it has to work in both directions.
    func completeTask(_ taskID: UUID, routineID: UUID? = nil) async {
        let targetID = routineID ?? activeRoutine()?.routineID
        guard let targetID,
              let index = activeRoutines.firstIndex(where: { $0.routineID == targetID }),
              let taskIndex = activeRoutines[index].taskCompletions.firstIndex(where: { $0.taskID == taskID })
        else { return }

        activeRoutines[index].taskCompletions[taskIndex].completedAt =
            activeRoutines[index].taskCompletions[taskIndex].completedAt == nil ? Date() : nil

        let updated = activeRoutines[index]
        refreshDerivedState()

        do {
            try persistRuntime()
            try await executionRepository.save(
                RoutineExecution(
                    id: updated.id,
                    routineID: updated.routineID,
                    routineName: updated.nameSnapshot,
                    startedAt: updated.startedAt,
                    taskCompletions: updated.taskCompletions
                )
            )
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Breaks

    /// Starts a break on one routine.
    ///
    /// The routine has to be named, because a break belongs to one: it lifts that
    /// routine's blocks and nothing else, and it is counted against that routine's own
    /// limit and cooldown. With several running, "take a break" is not a whole question.
    func startBreak(routineID: UUID? = nil, trigger: BreakTrigger) async {
        let targetID = routineID ?? activeRoutine()?.routineID
        guard let targetID, let target = activeRoutine(id: targetID) else { return }

        switch await breakAvailability(for: targetID, trigger: trigger, requiresFriction: false) {
        case .available:
            break
        case .unavailable(let unavailable):
            state = .failed(unavailable.message)
            refreshDerivedState()
            return
        }

        do {
            let existing = try await executionRepository.execution(id: target.id)
            let activeBreak = ActiveBreak(
                routineID: targetID,
                startedAt: Date(),
                endsAt: Date().addingTimeInterval(target.breakPolicySnapshot.maximumDuration),
                trigger: trigger
            )

            activeBreaks.removeAll { $0.routineID == targetID }
            activeBreaks.append(activeBreak)
            refreshDerivedState()

            try await applyShields()
            try await deviceActivityService.scheduleBreakEnd(activeBreak)

            var execution = existing ?? RoutineExecution(
                id: target.id,
                routineID: target.routineID,
                routineName: target.nameSnapshot,
                startedAt: target.startedAt,
                taskCompletions: target.taskCompletions
            )
            execution.breakHistory.append(
                RoutineBreakRecord(
                    id: activeBreak.id,
                    startedAt: activeBreak.startedAt,
                    trigger: trigger
                )
            )
            try await executionRepository.save(execution)
        } catch {
            activeBreaks.removeAll { $0.routineID == targetID }
            refreshDerivedState()
            state = .failed(error.localizedDescription)
        }
    }

    func breakAvailability(
        for routineID: UUID?,
        trigger: BreakTrigger,
        requiresFriction: Bool
    ) async -> BreakAvailability {
        guard let routineID, let activeRoutine = activeRoutine(id: routineID) else {
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

            // A break's endedAt is only written by endBreak, which needs the app to be
            // running when the break expires. One that ran out in the background -- the
            // monitor extension clears it and nothing writes the end -- left a record
            // with no endedAt at all, so `max()` was nil and the cooldown simply never
            // applied. The break's own duration says when it was over, so an unfinished
            // record falls back to that rather than being skipped.
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

    /// The strictest answer among every running routine that blocks this app.
    ///
    /// An app two routines hold shut cannot be let out by asking one of them: both have
    /// to agree, so the first refusal is the answer. Without this, taking a break on the
    /// routine that happened to be first would appear to unlock an app the other one is
    /// still blocking, and the shield would go straight back up.
    func breakAvailability(
        forApp appID: AppIdentity.ID,
        trigger: BreakTrigger,
        requiresFriction: Bool
    ) async -> BreakAvailability {
        let blocking = activeRoutines(blocking: appID)
        guard !blocking.isEmpty else {
            return await breakAvailability(
                for: activeRoutine()?.routineID,
                trigger: trigger,
                requiresFriction: requiresFriction
            )
        }

        for routine in blocking {
            let availability = await breakAvailability(
                for: routine.routineID,
                trigger: trigger,
                requiresFriction: requiresFriction
            )
            if case .unavailable = availability {
                return availability
            }
        }

        return .available
    }

    /// Ends the break on one routine and puts that routine's blocks back.
    func endBreak(routineID: UUID, reason: RoutineCompletionReason = .naturalCompletion) async {
        guard let target = activeRoutine(id: routineID),
              let running = activeBreak(for: routineID)
        else { return }

        do {
            var execution = try await executionRepository.execution(id: target.id) ?? RoutineExecution(
                id: target.id,
                routineID: target.routineID,
                routineName: target.nameSnapshot,
                startedAt: target.startedAt,
                taskCompletions: target.taskCompletions
            )
            if let index = execution.breakHistory.firstIndex(where: { $0.id == running.id }) {
                execution.breakHistory[index].endedAt = Date()
            }
            try await executionRepository.save(execution)

            activeBreaks.removeAll { $0.routineID == routineID }
            refreshDerivedState()

            try await applyShields()
            print("Routine break ended routineID=\(routineID.uuidString) restoring routine shields")
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Closes every break whose clock has run out.
    func endBreakIfNeeded(reason: RoutineCompletionReason = .naturalCompletion) async {
        for expired in activeBreaks.filter({ $0.endsAt <= Date() }) {
            await endBreak(routineID: expired.routineID, reason: reason)
        }
    }

    // MARK: - Shields

    /// Recomputes the shield from everything running and applies it.
    ///
    /// One place, called after every change. The policy is built from scratch each time
    /// rather than being added to and subtracted from, which is what lets a routine end
    /// without anything having to work out which of its apps another routine still wants
    /// blocked -- it is simply no longer in the list the union is built from.
    private func applyShields(clearPending: Bool = false) async throws {
        let pauseRules = await pauseRuleRepository.rules()
        let shieldRules = appGroupStore.loadShieldRules()
        let stored = try? appGroupStore.loadRuntimeState()
        let storedPolicy = stored?.shieldPolicy ?? .empty

        // An allowance exists to let an app through a routine's shield. With nothing left
        // running there is nothing for it to open, so it is not carried into the result.
        let allowance = activeRoutines.isEmpty ? nil : stored?.livePauseAllowance

        let effectivePolicy = shieldPolicyResolver.resolve(
            activeRoutines: activeRoutines,
            activeBreaks: activeBreaks,
            activePauseAllowance: allowance,
            pauseRules: pauseRules,
            rules: shieldRules.rules,
            ruleEnforcement: shieldRules.enforcement
        )

        try appGroupStore.updateRuntimeState { runtime in
            runtime.activeRoutines = activeRoutines
            runtime.activeBreaks = activeBreaks
            runtime.shieldPolicy = effectivePolicy

            if clearPending, activeRoutines.isEmpty {
                // Everything the last routine was carrying goes with it: the allowance it
                // granted, the unlock the shield left waiting, the events queued behind
                // them. These outlived the routine and kept the pending-unlock card on
                // Today for a routine that had already ended.
                runtime.activePauseAllowance = nil
                runtime.pendingPause = nil
                runtime.pendingEvents = []
                runtime.recoveryFlags = []
            }
        }

        if effectivePolicy.blocksNothing {
            try await shieldService.remove(storedPolicy)
        } else {
            try await shieldService.apply(effectivePolicy)
        }
    }

    private func persistRuntime() throws {
        try appGroupStore.updateRuntimeState { runtime in
            runtime.activeRoutines = activeRoutines
            runtime.activeBreaks = activeBreaks
        }
    }

    /// Pulls in anything the extensions started or ended while the app was not looking.
    ///
    /// The monitor extension writes straight to the App Group, so a scheduled routine can
    /// begin or end with this engine holding a list that predates it.
    private func synchronizeWithStoredState() async {
        guard let stored = try? appGroupStore.loadRuntimeState() else { return }
        activeRoutines = stored.activeRoutines
        activeBreaks = stored.activeBreaks
        refreshDerivedState()
    }

    private func finalizeExecution(
        activeRoutine: ActiveRoutine,
        endedAt: Date,
        completionReason: RoutineCompletionReason
    ) async throws {
        var execution = try await executionRepository.execution(id: activeRoutine.id) ?? RoutineExecution(
            id: activeRoutine.id,
            routineID: activeRoutine.routineID,
            routineName: activeRoutine.nameSnapshot,
            startedAt: activeRoutine.startedAt
        )
        execution.endedAt = endedAt
        execution.completionReason = completionReason
        execution.taskCompletions = activeRoutine.taskCompletions
        try await executionRepository.save(execution)
    }
}
