import Foundation

@MainActor
final class EditorViewModelStore {
    private var routineEditors: [UUID: RoutineEditorViewModel] = [:]
    private var pauseEditors: [UUID: PauseEditorViewModel] = [:]

    func routineEditor(
        route: RoutineEditorRoute,
        repository: RoutineRepository,
        selectionStore: ScreenTimeSelectionStore,
        routineEngine: RoutineEngine,
        usageDataService: UsageDataServicing
    ) -> RoutineEditorViewModel {
        if let existing = routineEditors[route.draftID] {
            return existing
        }

        let created = RoutineEditorViewModel(
            routineID: route.routineID,
            repository: repository,
            selectionStore: selectionStore,
            routineEngine: routineEngine,
            usageDataService: usageDataService
        )
        routineEditors[route.draftID] = created
        return created
    }

    func existingRoutineEditor(draftID: UUID) -> RoutineEditorViewModel? {
        routineEditors[draftID]
    }

    func pauseEditor(
        route: PauseEditorRoute,
        repository: PauseRuleRepository,
        selectionStore: ScreenTimeSelectionStore
    ) -> PauseEditorViewModel {
        if let existing = pauseEditors[route.draftID] {
            return existing
        }

        let created = PauseEditorViewModel(
            pauseID: route.pauseID,
            repository: repository,
            selectionStore: selectionStore
        )
        pauseEditors[route.draftID] = created
        return created
    }

    func releaseRoutineEditor(draftID: UUID) {
        routineEditors.removeValue(forKey: draftID)
    }

    func releasePauseEditor(draftID: UUID) {
        pauseEditors.removeValue(forKey: draftID)
    }
}
