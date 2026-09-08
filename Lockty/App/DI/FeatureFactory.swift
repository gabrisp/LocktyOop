import DeviceActivity
import Foundation
import FamilyControls
import ManagedSettings
import SwiftUI

struct FeatureFactory {
    let router: AppRouter
    let todayViewModel: TodayViewModel
    let rulesViewModel: RulesViewModel
    let routinesViewModel: RoutinesViewModel
    let focusViewModel: FocusViewModel
    let frictionsViewModel: FrictionsViewModel
    let pausesViewModel: PausesViewModel
    let lifetimeViewModel: LifetimeViewModel
    let systemAccessViewModel: SystemAccessViewModel
    let selectionStore: ScreenTimeSelectionStore
    let pauseEngine: PauseEngine
    let routineEngine: RoutineEngine
    let ruleRepository: RuleRepository
    let routineRepository: RoutineRepository
    let routineExecutionRepository: RoutineExecutionRepository
    let pauseRuleRepository: PauseRuleRepository
    let pauseFlowRepository: PauseFlowRepository
    let frictionRepository: FrictionRepository
    let pauseEventRepository: PauseEventRepository
    let classificationRepository: AppClassificationRepository
    let appGroupRepository: UserAppGroupRepository
    let autoFocusManager: AutoFocusManager
    let objectivesViewModel: ObjectivesViewModel
    /// One rules model for the card on Today and the screen behind it: two of them would
    /// be two answers to "how many ran".
    let ruleStatsViewModel: RuleStatsViewModel
    let appsViewModel: AppsLibraryViewModel
    let distractingGroupViewModel: DistractingGroupViewModel
    let haptics: HapticsProviding
    let nfcService: NFCServicing
    let locationService: LocationTriggerServicing
    let healthService: HealthServicing
    let toastCenter: LocktyToastCenter
    let editorStore: EditorViewModelStore
    let usageDataService: UsageDataServicing
    let quickTimerViewModel: QuickTimerViewModel
    /// One instance, because two screens edit the same stored preferences and a second
    /// copy would show a stale style the moment the first one changed it.
    let settingsViewModel: SettingsViewModel

    func makeTodayView(day: Date) -> TodayView {
        TodayView(
            day: day,
            viewModel: todayViewModel,
            objectivesViewModel: objectivesViewModel,
            ruleStatsViewModel: ruleStatsViewModel,
            router: router
        )
    }

    func makeFocusView() -> FocusView {
        FocusView(
            viewModel: focusViewModel,
            rulesViewModel: rulesViewModel,
            frictionsViewModel: frictionsViewModel,
            appsViewModel: appsViewModel,
            router: router,
            frictionRepository: frictionRepository,
            toastCenter: toastCenter,
            quickTimer: quickTimerViewModel,
            todayViewModel: todayViewModel
        )
    }

    func makeRulesList() -> some View {
        LocktySectionScreen(title: "Rules") {
            RulesView(viewModel: rulesViewModel, router: router)
        }
    }

    func makeLifetimeView() -> LifetimeView {
        LifetimeView(viewModel: lifetimeViewModel, router: router)
    }

    func makeSystemAccessSheet() -> SystemAccessSheet {
        SystemAccessSheet(viewModel: systemAccessViewModel)
    }

    func makeBreakStatusSheet(state: BreakUnavailableState) -> BreakStatusSheet {
        BreakStatusSheet(state: state)
    }

    func makeAllowanceTimerSheet(route: AllowanceTimerRoute) -> AllowanceTimerSheet {
        AllowanceTimerSheet(route: route)
    }

    func makeDayPickerSheet() -> DayPickerSheet {
        DayPickerSheet(
            selectedDay: Binding(
                get: { router.selectedDay },
                set: { router.selectedDay = Calendar.current.startOfDay(for: $0) }
            )
        )
    }

    /// The streak, in a sheet of its own.
    ///
    /// A fresh view model each time it is opened, on purpose: it is a read of the last
    /// ninety days and it should be the read as of now, not as of whenever the sheet was
    /// first built.
    func makeObjectiveEditor(objectiveID: UUID?) -> ObjectiveEditorSheet {
        ObjectiveEditorSheet(
            objective: objectiveID.flatMap { id in
                objectivesViewModel.objectives.first { $0.id == id }
            },
            viewModel: objectivesViewModel,
            onSave: { objectivesViewModel.save($0) },
            onDelete: { objectivesViewModel.delete($0) }
        )
    }

    func makeQuickShieldSheet() -> some View {
        QuickShieldSheet(
            viewModel: quickTimerViewModel,
            frictionsViewModel: frictionsViewModel,
            toastCenter: toastCenter,
            onClose: { router.dismissSheet() }
        )
    }

    func makeRuleStats() -> RuleStatsView {
        RuleStatsView(viewModel: ruleStatsViewModel, router: router)
    }

    func makeObjectives(focused: UUID? = nil) -> ObjectivesView {
        ObjectivesView(viewModel: objectivesViewModel, router: router, initialFocus: focused)
    }

    func makeStreakSheet() -> some View {
        LocktyDynamicSheet {
            StreakSheet(
                viewModel: StreakViewModel(routineExecutionRepository: routineExecutionRepository)
            )
        }
    }

    func makeSettingsView() -> SettingsView {
        SettingsView(
            viewModel: settingsViewModel,
            access: systemAccessViewModel,
            router: router,
            onKillEverything: { await killEverything() },
            onResumeEnforcement: { await resumeEnforcement() }
        )
    }

    /// Lets everything arm again.
    ///
    /// The other half of the switch: without it the kill is permanent for that install,
    /// because every path that would rebuild the policy is now asking a flag that says no.
    func resumeEnforcement() async {
        DebugKillSwitch.set(false)
        await pauseEngine.refreshShields()
    }

    /// Tears every block down, in the order that leaves nothing holding on.
    ///
    /// Debug only -- the button that calls it is compiled out of release builds. Each step
    /// undoes a different keeper of the same fact: the engine holds the routines, the
    /// shield service holds ManagedSettings, the runtime state is what the extensions read
    /// when the app is not running, and DeviceActivity holds the monitors that would put
    /// half of it back at the next threshold.
    ///
    /// Nothing is deleted. Rules, modes, frictions and objectives are all still there when
    /// it is done: this stops what is running, it does not empty the library.
    func killEverything() async {
        // The latch first, so anything that runs while this is working finds enforcement
        // already switched off rather than helpfully rebuilding it behind us.
        DebugKillSwitch.set(true)

        // Every routine, not one: `stop()` with no id ends them all.
        await routineEngine.stop()

        // The shared container is a path and a coder, so one made here is the same store
        // the extensions read.
        let store = AppGroupStore()
        store.resetRuntimeStateToSafeDefault()
        try? store.saveRuleEnforcementState(.empty)
        try? store.saveRulePauseState(.empty)

        // The monitors that would put half of it back at the next threshold.
        DeviceActivityCenter().stopMonitoring()

        // And no `refreshShields` at the end, deliberately. That is the call every other
        // change finishes with, and here it would recompute the policy from the stored
        // rules and put every shield straight back -- the kill would have lasted about a
        // second. The latch above is what keeps the next one from doing it either.
        await pauseEngine.clearShields()
    }

    func makeAutoFocusSheet() -> DistractingGroupSheet {
        DistractingGroupSheet(
            viewModel: distractingGroupViewModel,
            frictions: frictionsViewModel.frictions,
            toastCenter: toastCenter,
            manager: autoFocusManager
        )
    }

    func makeAlwaysAllowedSheet() -> AlwaysAllowedSheet {
        AlwaysAllowedSheet(
            viewModel: appsViewModel,
            toastCenter: toastCenter,
            selectionStore: selectionStore
        )
    }

    func makeBlockScreenSettings() -> BlockScreenSettingsView {
        BlockScreenSettingsView(viewModel: settingsViewModel)
    }

    @ViewBuilder
    func makeLiveSessionSheet() -> some View {
        if let routine = routineEngine.activeRoutine() {
            LiveSessionSheet(
                routine: routine,
                pauseEvents: pausesViewModel.eventsSince(routine.startedAt),
                onStop: {
                    Task {
                        await routineEngine.stop()
                        router.dismissSheet()
                    }
                }
            )
        }
    }

    func makeRoutinesList() -> some View {
        LocktySectionScreen(title: "Routines") {
            RoutinesView(viewModel: routinesViewModel, router: router)
        }
    }

    func makeFrictionsList() -> some View {
        LocktySectionScreen(title: "Frictions") {
            FrictionsView(viewModel: frictionsViewModel, router: router)
        }
    }

    func makeAppsList() -> some View {
        LocktySectionScreen(title: "Apps") {
            AppsListView(viewModel: appsViewModel, router: router)
        }
    }

    func makeDistractingGroup() -> some View {
        DistractingGroupView(viewModel: distractingGroupViewModel, router: router)
    }

    func makeAlwaysAllowedGroupView() -> some View {
        AlwaysAllowedGroupView(viewModel: appsViewModel, router: router)
    }

    func makeDistractingAppsSelection() -> some View {
        DistractingAppsSelectionView(manager: autoFocusManager, toastCenter: toastCenter, router: router)
    }

    func makeDistractingInterventionPicker() -> some View {
        DistractingInterventionPickerView(viewModel: distractingGroupViewModel, router: router)
    }

    func makeDistractingFrictionPicker() -> some View {
        DistractingFrictionPickerView(
            viewModel: distractingGroupViewModel,
            frictionRepository: frictionRepository,
            router: router
        )
    }

    func makeAppGroupEditor(route: AppGroupEditorRoute) -> some View {
        AppGroupEditorView(
            viewModel: editorStore.appGroupEditor(
                route: route,
                repository: appGroupRepository,
                selectionStore: selectionStore
            ),
            router: router,
            toastCenter: toastCenter,
            onCloseEditor: { editorStore.releaseAppGroupEditor(draftID: route.draftID) }
        )
    }

    func makeFocusCreationChoiceSheet(route: FocusCreationChoiceRoute) -> FocusCreationChoiceSheet {
        FocusCreationChoiceSheet(
            router: router,
            makeRuleEditor: { onReturnToParent in
                AnyView(
                    RuleEditorView(
                        viewModel: editorStore.ruleEditor(
                            route: RuleEditorRoute(
                                ruleID: nil,
                                draftID: route.ruleDraftID,
                                routineDraftID: route.routineDraftID
                            ),
                            repository: ruleRepository,
                            selectionStore: selectionStore,
                            frictionRepository: frictionRepository,
                            appGroupRepository: appGroupRepository,
                            toastCenter: toastCenter,
                            pauseEngine: pauseEngine
                        ),
                        makeScheduleRuleEditor: { onReturnToRuleChoice in
                            AnyView(
                                RoutineEditorView(
                                    viewModel: editorStore.routineEditor(
                                        route: RoutineEditorRoute(routineID: nil, draftID: route.routineDraftID),
                                        repository: routineRepository,
                                        selectionStore: selectionStore,
                                        routineEngine: routineEngine,
                                        pauseEngine: pauseEngine,
                                        usageDataService: usageDataService,
                                        pauseFlowRepository: pauseFlowRepository,
                                        appGroupRepository: appGroupRepository,
                                        toastCenter: toastCenter
                                    ),
                                    router: router,
                                    startsEditing: true,
                                    isEmbeddedInParentSheet: true,
                                    onReturnToParent: onReturnToRuleChoice,
                                    onCloseEditor: { editorStore.releaseRoutineEditor(draftID: route.routineDraftID) }
                                )
                            )
                        },
                        isEmbeddedInParentSheet: true,
                        onReturnToParent: onReturnToParent,
                        onCloseEditor: { editorStore.releaseRuleEditor(draftID: route.ruleDraftID) }
                    )
                )
            },
            makeFrictionEditor: { onReturnToParent in
                AnyView(
                    FrictionEditorView(
                        viewModel: editorStore.frictionEditor(
                            route: FrictionEditorRoute(frictionID: nil, draftID: route.frictionDraftID),
                            repository: frictionRepository,
                            routineRepository: routineRepository
                        ),
                        isEmbeddedInParentSheet: true,
                        locationService: locationService,
                        onReturnToParent: onReturnToParent,
                        onCloseEditor: { editorStore.releaseFrictionEditor(draftID: route.frictionDraftID) }
                    )
                )
            },
            releaseRuleEditor: { editorStore.releaseRuleEditor(draftID: route.ruleDraftID) },
            releaseFrictionEditor: { editorStore.releaseFrictionEditor(draftID: route.frictionDraftID) }
        )
    }

    func makeUnlockFlow(route: UnlockFlowRoute) -> UnlockFlowView {
        // Everything every running routine is holding shut, not just the first one's.
        // The flow's app picker offers what can be unlocked, and with two routines
        // running it was offering half of it.
        let requestContext = route.context
        let token = requestContext?.applicationToken ?? route.token
        let running = routineEngine.activeRoutines
        var blockedSelection = running.reduce(into: Set<ApplicationToken>()) { result, routine in
            let selection = selectionStore.blockedSelection(scopes: routine.shieldPolicy.selectionScopes)
            result.formUnion(selection.applicationTokens)
        }
        if let token {
            blockedSelection.insert(token)
        }
        let blockedTokens = blockedSelection.stablePrefix(blockedSelection.count)

        // The friction to walk is the one belonging to a routine that actually blocks the
        // app being asked about. Falling back to whichever routine started first would
        // put up a friction that has nothing to do with the app in hand.
        let appID = token.map(AppIdentity.ID.init(token:)) ?? requestContext?.appID
        let blocking = appID.map { id in
            running.filter { routine in
                if routine.shieldPolicy.blockedApplications.contains(id) {
                    return true
                }
                let selection = selectionStore.blockedSelection(scopes: routine.shieldPolicy.selectionScopes)
                return selection.applicationTokens.contains { AppIdentity.ID(token: $0) == id }
            }
        } ?? []
        let activeRoutine = requestContext?.activeRoutineID
            .flatMap { routineID in running.first { $0.routineID == routineID } }
            ?? blocking.routineAnsweringForApp
            ?? routineEngine.activeRoutine()
        let allowanceMinutes = max(
            1,
            Int((requestContext?.allowanceDuration
                ?? activeRoutine?.pausePolicySnapshot.allowanceDuration
                ?? 300) / 60)
        )
        let requestedSteps = requestContext?.steps ?? []
        let flowSteps = requestedSteps.isEmpty ? (activeRoutine?.pausePolicySnapshot.steps ?? []) : requestedSteps

        return UnlockFlowView(
            tokens: blockedTokens,
            initialToken: token,
            frictionSteps: flowSteps,
            breatheSeconds: activeRoutine?.pausePolicySnapshot.breatheSeconds ?? LocktyBreathe.minimumSeconds,
            // The allowance is a ceiling, not a figure.
            //
            // Choosing "five minutes" on a routine says how long an unlock may last at
            // most; the wheel then offers one to five, so a minute is sayable when a
            // minute is all that is needed. The range was never passed at all, so the
            // wheel sat on its own default of one to fifteen and offered fifteen minutes
            // on a routine that had granted five -- and five on one that had granted
            // thirty.
            allowanceRange: 1...allowanceMinutes,
            defaultMinutes: allowanceMinutes,
            nfcService: nfcService,
            locationService: locationService,
            healthService: healthService
        ) { chosenToken, minutes, intention in
            Task { @MainActor in
                // Checked against every routine holding the chosen app, not just one:
                // all of them have to agree before it comes out.
                if requestContext?.limitRuleID != nil {
                    // Limit rules were already checked when the shield request was
                    // presented. They are not routine breaks, so asking the routine
                    // engine here rejects valid limit unlocks.
                } else if let chosenID = chosenToken.map(AppIdentity.ID.init(token:)) {
                    switch await routineEngine.breakAvailability(
                        forApp: chosenID,
                        trigger: .manual,
                        requiresFriction: true
                    ) {
                    case .available:
                        break
                    case .unavailable(let unavailable):
                        router.dismissFullScreen()
                        router.presentSheet(.breakStatus(unavailable))
                        return
                    }
                } else if let activeRoutine {
                    switch await routineEngine.breakAvailability(
                        for: activeRoutine.routineID,
                        trigger: .manual,
                        requiresFriction: true
                    ) {
                    case .available:
                        break
                    case .unavailable(let unavailable):
                        router.dismissFullScreen()
                        router.presentSheet(.breakStatus(unavailable))
                        return
                    }
                }
                await grantAllowance(
                    for: chosenToken,
                    among: blockedTokens,
                    minutes: minutes,
                    activeRoutine: activeRoutine,
                    requestContext: requestContext,
                    intention: intention
                )
                // Before the flow closes, so the card behind it is already right. The
                // unlock spends a break and starts a cooldown on everything else that
                // routine holds, and nothing recomputed either: the rings stayed green
                // with no countdown until the app was backgrounded and brought back.
                await todayViewModel.refreshActiveRoutineState()
                router.dismissFullScreen()
            }
        } onClose: {
            router.dismissFullScreen()
        }
    }

    /// Opens the friction for a limit that is holding its apps right now.
    ///
    /// The context is built here rather than in the editor because a limit's unlock is the
    /// same object the shield builds when you walk into one of its apps -- a `PauseContext`
    /// carrying `limitRuleID`, which is what tells `makeUnlockFlow` to skip the routine
    /// break check. Without it the flow would ask the routine engine about a break that
    /// belongs to no routine, and be refused every time.
    private func presentLimitUnlock(ruleID: UUID) {
        guard let rule = AppGroupStore().loadStoredRules().first(where: { $0.id == ruleID }) else {
            return
        }

        let selection = selectionStore.blockedSelection(scopes: rule.selectionScopes)
        let tokens = selection.applicationTokens
        guard let representative = tokens.stablePrefix(1).first else { return }

        let identity = AppIdentity(token: representative)
        let context = PauseContext(
            pauseRuleID: rule.id,
            appID: identity.id,
            applicationToken: representative,
            // Every app the limit holds, because the limit holds them together: spending
            // its break on one and leaving the rest shut is not what the rule says.
            releasedApplications: Set(tokens.map(AppIdentity.ID.init(token:))),
            displayName: identity.displayName,
            allowanceDuration: TimeInterval(max(rule.breakPolicy.durationMinutes ?? 5, 1) * 60),
            steps: rule.breakPolicy.frictionPolicy.steps,
            limitRuleID: rule.id,
            source: .app
        )

        router.dismissSheet()
        router.presentFullScreen(.unlockFlow(UnlockFlowRoute(context: context)))
    }

    /// Grants the allowance the flow just asked for.
    ///
    /// A nil token is the flow's "all apps" choice: it releases everything the routine
    /// is holding shut rather than nothing, which is what it did while an allowance
    /// could only ever name one app.
    private func grantAllowance(
        for token: ApplicationToken?,
        among blockedTokens: [ApplicationToken],
        minutes: Int,
        activeRoutine: ActiveRoutine?,
        requestContext: PauseContext?,
        intention: String?
    ) async {
        let fallbackReleased = blockedTokens.isEmpty
            ? requestContext?.applicationToken.map { [$0] } ?? []
            : blockedTokens
        let released = token.map { [$0] } ?? fallbackReleased
        guard let representative = released.first else { return }

        let identity = AppIdentity(token: representative)
        let releasedIDs = Set(released.map(AppIdentity.ID.init(token:)))
        var context = requestContext ?? PauseContext(
            pauseRuleID: activeRoutine?.routineID ?? identity.id.rawValue.stableUUID,
            appID: identity.id,
            applicationToken: representative,
            releasedApplications: releasedIDs,
            displayName: token == nil ? "All apps" : identity.displayName,
            allowanceDuration: TimeInterval(minutes * 60),
            // No steps: the wait already happened in the flow itself. This grants the
            // allowance it settled on.
            steps: [],
            activeRoutineID: activeRoutine?.routineID,
            source: .app
        )
        context.applicationToken = representative
        context.appID = token.map(AppIdentity.ID.init(token:)) ?? context.appID
        context.releasedApplications = releasedIDs.isEmpty ? context.releasedApplications : releasedIDs
        context.displayName = token == nil && !blockedTokens.isEmpty ? "All apps" : identity.displayName
        context.allowanceDuration = TimeInterval(minutes * 60)
        context.steps = []
        context.activeRoutineID = activeRoutine?.routineID ?? context.activeRoutineID
        await pauseEngine.allowTemporarily(context, intention: intention)
        toastCenter.show(
            .unlockGranted(
                token: token,
                displayName: context.displayName,
                minutes: minutes
            )
        )
        await recordAllowanceBreakIfNeeded(
            activeRoutine: activeRoutine,
            duration: context.allowanceDuration,
            trigger: .manual
        )
    }

    private func recordAllowanceBreakIfNeeded(
        activeRoutine: ActiveRoutine?,
        duration: TimeInterval,
        trigger: BreakTrigger
    ) async {
        guard let activeRoutine else { return }
        guard case .temporarilyAllowed(let allowance) = pauseEngine.state,
              allowance.context.activeRoutineID == activeRoutine.routineID
        else {
            return
        }

        do {
            var execution = try await routineExecutionRepository.execution(id: activeRoutine.id) ?? RoutineExecution(
                id: activeRoutine.id,
                routineID: activeRoutine.routineID,
                routineName: activeRoutine.nameSnapshot,
                startedAt: activeRoutine.startedAt,
                taskCompletions: activeRoutine.taskCompletions
            )
            let startedAt = Date()
            execution.breakHistory.append(
                RoutineBreakRecord(
                    startedAt: startedAt,
                    endedAt: startedAt.addingTimeInterval(duration),
                    trigger: trigger
                )
            )
            try await routineExecutionRepository.save(execution)
        } catch {
            print("Recording allowance break failed: \(error.localizedDescription)")
        }
    }

    func makePauseFlowEditor(route: PauseFlowEditorRoute) -> PauseFlowEditorSheet {
        PauseFlowEditorSheet(
            viewModel: PauseFlowEditorViewModel(
                flowID: route.flowID,
                repository: pauseFlowRepository
            )
        )
    }

    func makeRoutineDetail(routineID: UUID) -> RoutineDetailView {
        RoutineDetailView(
            viewModel: RoutineDetailViewModel(
                routineID: routineID,
                repository: routineRepository,
                executionRepository: routineExecutionRepository,
                routineEngine: routineEngine,
                selectionStore: selectionStore
            ),
            router: router
        )
    }

    func makeRoutineEditor(route: RoutineEditorRoute) -> RoutineEditorView {
        RoutineEditorView(
            viewModel: editorStore.routineEditor(
                route: route,
                repository: routineRepository,
                selectionStore: selectionStore,
                routineEngine: routineEngine,
                pauseEngine: pauseEngine,
                usageDataService: usageDataService,
                pauseFlowRepository: pauseFlowRepository,
                appGroupRepository: appGroupRepository,
                toastCenter: toastCenter
            ),
            router: router,
            startsEditing: route.startsEditing,
            onCloseEditor: { editorStore.releaseRoutineEditor(draftID: route.draftID) }
        )
    }

    func makeRuleEditor(route: RuleEditorRoute) -> RuleEditorView {
        RuleEditorView(
            viewModel: editorStore.ruleEditor(
                route: route,
                repository: ruleRepository,
                selectionStore: selectionStore,
                frictionRepository: frictionRepository,
                appGroupRepository: appGroupRepository,
                toastCenter: toastCenter,
                pauseEngine: pauseEngine
            ),
            startsAtLimitKind: route.startsAtLimitKind,
            onStartFriction: route.ruleID.map { ruleID in
                { presentLimitUnlock(ruleID: ruleID) }
            },
            makeScheduleRuleEditor: { onReturnToRuleChoice in
                AnyView(
                    RoutineEditorView(
                        viewModel: editorStore.routineEditor(
                            route: RoutineEditorRoute(
                                routineID: route.ruleID,
                                draftID: route.routineDraftID,
                                startsEditing: route.ruleID == nil
                            ),
                            repository: routineRepository,
                            selectionStore: selectionStore,
                            routineEngine: routineEngine,
                            pauseEngine: pauseEngine,
                            usageDataService: usageDataService,
                            pauseFlowRepository: pauseFlowRepository,
                            appGroupRepository: appGroupRepository,
                            toastCenter: toastCenter
                        ),
                        router: router,
                        startsEditing: route.ruleID == nil,
                        isEmbeddedInParentSheet: true,
                        onReturnToParent: onReturnToRuleChoice,
                        onCloseEditor: { editorStore.releaseRoutineEditor(draftID: route.routineDraftID) }
                    )
                )
            },
            onCloseEditor: { editorStore.releaseRuleEditor(draftID: route.draftID) }
        )
    }

    func makeApplicationDetails(appID: AppIdentity.ID, day: Date?) -> ApplicationDetailView {
        ApplicationDetailView(
            viewModel: ApplicationDetailViewModel(
                appID: appID,
                day: day ?? router.selectedDay,
                todayViewModel: todayViewModel,
                routineRepository: routineRepository,
                pauseRuleRepository: pauseRuleRepository
            ),
            router: router
        )
    }

    func makePauseDetail(pauseID: UUID) -> PauseDetailView {
        PauseDetailView(
            viewModel: PauseDetailViewModel(
                pauseID: pauseID,
                repository: pauseRuleRepository,
                eventRepository: pauseEventRepository
            ),
            router: router
        )
    }

    func makePauseEditor(route: PauseEditorRoute) -> PauseEditorView {
        PauseEditorView(
            viewModel: editorStore.pauseEditor(
                route: route,
                repository: pauseRuleRepository,
                selectionStore: selectionStore,
                routineEngine: routineEngine,
                pauseEngine: pauseEngine,
                usageDataService: usageDataService
            ),
            toastCenter: toastCenter,
            router: router,
            onCloseEditor: { editorStore.releasePauseEditor(draftID: route.draftID) }
        )
    }

    func makeFrictionEditor(route: FrictionEditorRoute) -> FrictionEditorView {
        FrictionEditorView(
            viewModel: editorStore.frictionEditor(
                route: route,
                repository: frictionRepository,
                routineRepository: routineRepository
            ),
            locationService: locationService,
            onCloseEditor: { editorStore.releaseFrictionEditor(draftID: route.draftID) }
        )
    }

    func makeScoreDetail(day: Date, kind: PrimaryMetricKind) -> DailyScoreDetailView {
        DailyScoreDetailView(day: day, kind: kind, viewModel: todayViewModel)
    }

    func makeUsageBreakdown(day: Date) -> UsageBreakdownView {
        UsageBreakdownView(
            day: day,
            viewModel: UsageBreakdownViewModel(
                day: day,
                classificationRepository: classificationRepository,
                autoFocusManager: autoFocusManager
            )
        )
    }

    func makeScreenTimeInsights(day: Date) -> ScreenTimeInsightsView {
        ScreenTimeInsightsView(day: day, viewModel: todayViewModel)
    }

    func makeProductivityDetail(day: Date) -> ProductivityDetailView {
        ProductivityDetailView(day: day, viewModel: todayViewModel)
    }

    func makeControlDetail(day: Date) -> ControlDetailView {
        ControlDetailView(day: day, viewModel: todayViewModel)
    }

    func makeDetoxDetail(day: Date) -> DetoxDetailView {
        DetoxDetailView(day: day, viewModel: todayViewModel)
    }

    func makeScreenTimeDetail(day: Date) -> ScreenTimeDetailView {
        ScreenTimeDetailView(day: day, viewModel: todayViewModel)
    }

    func makeRoutineDaySummary(day: Date) -> RoutineDaySummaryView {
        RoutineDaySummaryView(day: day, viewModel: todayViewModel)
    }

    func makePauseDaySummary(day: Date) -> PauseDaySummaryView {
        PauseDaySummaryView(day: day, viewModel: todayViewModel)
    }

    func makeDigitalBalanceDetail(day: Date) -> DigitalBalanceDetailView {
        DigitalBalanceDetailView(day: day, viewModel: todayViewModel)
    }

    func makeClassificationSheet(appID: AppIdentity.ID) -> AppClassificationSheet {
        AppClassificationSheet(
            viewModel: AppClassificationSheetViewModel(
                appID: appID,
                repository: classificationRepository
            )
        )
    }

    func makeRoutineBreakSheet(routineID: UUID) -> RoutineBreakSheet {
        RoutineBreakSheet(
            viewModel: RoutineBreakSheetViewModel(
                routineID: routineID,
                routineEngine: routineEngine
            ),
            router: router
        )
    }

    func makeAppPickerSheet(scope: ScreenTimeSelectionScope) -> AppPickerSheet {
        AppPickerSheet(
            viewModel: AppPickerViewModel(selectionStore: selectionStore, scope: scope),
            toastCenter: toastCenter
        )
    }

    func makeActiveRoutine(routineID: UUID) -> ActiveRoutineView {
        ActiveRoutineView(
            viewModel: ActiveRoutineViewModel(
                routineID: routineID,
                routineEngine: routineEngine
            ),
            router: router
        )
    }
}
