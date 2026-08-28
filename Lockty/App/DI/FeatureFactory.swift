import Foundation
import SwiftUI

struct FeatureFactory {
    let router: AppRouter
    let todayViewModel: TodayViewModel
    let routinesViewModel: RoutinesViewModel
    let focusViewModel: FocusViewModel
    let pausesViewModel: PausesViewModel
    let lifetimeViewModel: LifetimeViewModel
    let systemAccessViewModel: SystemAccessViewModel
    let selectionStore: ScreenTimeSelectionStore
    let pauseEngine: PauseEngine
    let routineEngine: RoutineEngine
    let routineRepository: RoutineRepository
    let routineExecutionRepository: RoutineExecutionRepository
    let pauseRuleRepository: PauseRuleRepository
    let pauseEventRepository: PauseEventRepository
    let classificationRepository: AppClassificationRepository
    let haptics: HapticsProviding
    let editorStore: EditorViewModelStore
    let usageDataService: UsageDataServicing

    func makeTodayView(day: Date) -> TodayView {
        TodayView(day: day, viewModel: todayViewModel, router: router)
    }

    func makeFocusView() -> FocusView {
        FocusView(viewModel: focusViewModel, routinesViewModel: routinesViewModel, pausesViewModel: pausesViewModel, router: router)
    }

    func makeLifetimeView() -> LifetimeView {
        LifetimeView(viewModel: lifetimeViewModel)
    }

    func makeSystemAccessSheet() -> SystemAccessSheet {
        SystemAccessSheet(viewModel: systemAccessViewModel)
    }

    func makeSettingsView() -> SettingsView {
        SettingsView()
    }

    func makePauseView(context: PauseContext) -> PauseView {
        PauseView(
            viewModel: PauseViewModel(context: context, engine: pauseEngine),
            router: router
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
                usageDataService: usageDataService
            ),
            router: router,
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
                selectionStore: selectionStore
            ),
            router: router,
            onCloseEditor: { editorStore.releasePauseEditor(draftID: route.draftID) }
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
