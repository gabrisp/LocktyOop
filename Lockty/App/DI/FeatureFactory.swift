import Foundation
import FamilyControls
import ManagedSettings
import SwiftUI

struct FeatureFactory {
    let router: AppRouter
    let todayViewModel: TodayViewModel
    let routinesViewModel: RoutinesViewModel
    let focusViewModel: FocusViewModel
    let frictionsViewModel: FrictionsViewModel
    let pausesViewModel: PausesViewModel
    let lifetimeViewModel: LifetimeViewModel
    let systemAccessViewModel: SystemAccessViewModel
    let selectionStore: ScreenTimeSelectionStore
    let pauseEngine: PauseEngine
    let routineEngine: RoutineEngine
    let routineRepository: RoutineRepository
    let routineExecutionRepository: RoutineExecutionRepository
    let pauseRuleRepository: PauseRuleRepository
    let pauseFlowRepository: PauseFlowRepository
    let frictionRepository: FrictionRepository
    let pauseEventRepository: PauseEventRepository
    let classificationRepository: AppClassificationRepository
    let haptics: HapticsProviding
    let nfcService: NFCServicing
    let locationService: LocationTriggerServicing
    let editorStore: EditorViewModelStore
    let usageDataService: UsageDataServicing

    func makeTodayView(day: Date) -> TodayView {
        TodayView(day: day, viewModel: todayViewModel, router: router)
    }

    func makeFocusView() -> FocusView {
        FocusView(
            viewModel: focusViewModel,
            routinesViewModel: routinesViewModel,
            frictionsViewModel: frictionsViewModel,
            router: router,
            frictionRepository: frictionRepository
        )
    }

    func makeLifetimeView() -> LifetimeView {
        LifetimeView(viewModel: lifetimeViewModel, router: router)
    }

    func makeSystemAccessSheet() -> SystemAccessSheet {
        SystemAccessSheet(viewModel: systemAccessViewModel)
    }

    func makeSettingsView() -> SettingsView {
        SettingsView()
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

    func makeFocusCreationChoiceSheet(route: FocusCreationChoiceRoute) -> FocusCreationChoiceSheet {
        FocusCreationChoiceSheet(
            router: router,
            makeRoutineEditor: { onReturnToParent in
                AnyView(
                    RoutineEditorView(
                        viewModel: editorStore.routineEditor(
                            route: RoutineEditorRoute(routineID: nil, draftID: route.routineDraftID),
                            repository: routineRepository,
                            selectionStore: selectionStore,
                            routineEngine: routineEngine,
                            usageDataService: usageDataService,
                            pauseFlowRepository: pauseFlowRepository
                        ),
                        router: router,
                        startsEditing: true,
                        isEmbeddedInParentSheet: true,
                        onReturnToParent: onReturnToParent,
                        onCloseEditor: { editorStore.releaseRoutineEditor(draftID: route.routineDraftID) }
                    )
                )
            },
            makeFrictionEditor: { onReturnToParent in
                AnyView(
                    FrictionEditorView(
                        viewModel: editorStore.frictionEditor(
                            route: FrictionEditorRoute(frictionID: nil, draftID: route.frictionDraftID),
                            repository: frictionRepository
                        ),
                        isEmbeddedInParentSheet: true,
                        locationService: locationService,
                        onReturnToParent: onReturnToParent,
                        onCloseEditor: { editorStore.releaseFrictionEditor(draftID: route.frictionDraftID) }
                    )
                )
            },
            releaseRoutineEditor: { editorStore.releaseRoutineEditor(draftID: route.routineDraftID) },
            releaseFrictionEditor: { editorStore.releaseFrictionEditor(draftID: route.frictionDraftID) }
        )
    }

    func makeUnlockFlow(token: ApplicationToken?) -> UnlockFlowView {
        let activeRoutine = routineEngine.activeRoutine()
        let blockedTokens: [ApplicationToken] = activeRoutine.map { routine in
            let selection = (try? selectionStore.load(scope: .routine(routine.routineID)))?.applicationTokens ?? []
            return selection.stablePrefix(selection.count)
        } ?? []

        return UnlockFlowView(
            tokens: blockedTokens,
            initialToken: token,
            frictionSteps: activeRoutine?.pausePolicySnapshot.steps ?? [],
            defaultMinutes: Int((activeRoutine?.pausePolicySnapshot.allowanceDuration ?? 300) / 60),
            nfcService: nfcService,
            locationService: locationService
        ) { chosenToken, minutes, intention in
            Task { @MainActor in
                await grantAllowance(
                    for: chosenToken,
                    among: blockedTokens,
                    minutes: minutes,
                    activeRoutine: activeRoutine,
                    intention: intention
                )
                router.dismissFullScreen()
            }
        } onClose: {
            router.dismissFullScreen()
        }
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
        intention: String?
    ) async {
        let released = token.map { [$0] } ?? blockedTokens
        guard let representative = released.first else { return }

        let identity = AppIdentity(token: representative)
        let releasedIDs = Set(released.map(AppIdentity.ID.init(token:)))
        let context = PauseContext(
            pauseRuleID: activeRoutine?.routineID ?? identity.id.rawValue.stableUUID,
            appID: identity.id,
            applicationToken: representative,
            releasedApplications: releasedIDs,
            displayName: token == nil ? "Todas las apps" : identity.displayName,
            allowanceDuration: TimeInterval(minutes * 60),
            // No steps: the wait already happened in the flow itself. This grants the
            // allowance it settled on.
            steps: [],
            activeRoutineID: activeRoutine?.routineID,
            source: .app
        )
        await pauseEngine.allowTemporarily(context, intention: intention)
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
                usageDataService: usageDataService,
                pauseFlowRepository: pauseFlowRepository
            ),
            router: router,
            startsEditing: route.startsEditing,
            onCloseEditor: { editorStore.releaseRoutineEditor(draftID: route.draftID) }
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
            router: router,
            onCloseEditor: { editorStore.releasePauseEditor(draftID: route.draftID) }
        )
    }

    func makeFrictionEditor(route: FrictionEditorRoute) -> FrictionEditorView {
        FrictionEditorView(
            viewModel: editorStore.frictionEditor(
                route: route,
                repository: frictionRepository
            ),
            locationService: locationService,
            onCloseEditor: { editorStore.releaseFrictionEditor(draftID: route.draftID) }
        )
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

    func makeDistractionsDetail(day: Date) -> DistractionsDetailView {
        DistractionsDetailView(day: day, viewModel: todayViewModel)
    }

    func makeIntentionalTimeDetail(day: Date) -> IntentionalTimeDetailView {
        IntentionalTimeDetailView(day: day, viewModel: todayViewModel)
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
        AppPickerSheet(viewModel: AppPickerViewModel(selectionStore: selectionStore, scope: scope))
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
