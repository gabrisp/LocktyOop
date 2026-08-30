import Foundation

@MainActor
final class EditorViewModelStore {
    private var ruleEditors: [UUID: RuleEditorViewModel] = [:]
    private var routineEditors: [UUID: RoutineEditorViewModel] = [:]
    private var pauseEditors: [UUID: PauseEditorViewModel] = [:]
    private var frictionEditors: [UUID: FrictionEditorViewModel] = [:]
    private var appGroupEditors: [UUID: AppGroupEditorViewModel] = [:]

    func ruleEditor(
        route: RuleEditorRoute,
        repository: RuleRepository,
        selectionStore: ScreenTimeSelectionStore,
        frictionRepository: FrictionRepository
    ) -> RuleEditorViewModel {
        if let existing = ruleEditors[route.draftID] {
            return existing
        }

        let created = RuleEditorViewModel(
            ruleID: route.ruleID,
            draftID: route.draftID,
            repository: repository,
            selectionStore: selectionStore,
            frictionRepository: frictionRepository
        )
        ruleEditors[route.draftID] = created
        return created
    }

    func routineEditor(
        route: RoutineEditorRoute,
        repository: RoutineRepository,
        selectionStore: ScreenTimeSelectionStore,
        routineEngine: RoutineEngine,
        usageDataService: UsageDataServicing,
        pauseFlowRepository: PauseFlowRepository
    ) -> RoutineEditorViewModel {
        if let existing = routineEditors[route.draftID] {
            return existing
        }

        let created = RoutineEditorViewModel(
            routineID: route.routineID,
            draftID: route.draftID,
            repository: repository,
            selectionStore: selectionStore,
            routineEngine: routineEngine,
            usageDataService: usageDataService,
            pauseFlowRepository: pauseFlowRepository
        )
        routineEditors[route.draftID] = created
        return created
    }

    func pauseEditor(
        route: PauseEditorRoute,
        repository: PauseRuleRepository,
        selectionStore: ScreenTimeSelectionStore,
        routineEngine: RoutineEngine,
        pauseEngine: PauseEngine,
        usageDataService: UsageDataServicing
    ) -> PauseEditorViewModel {
        if let existing = pauseEditors[route.draftID] {
            return existing
        }

        let created = PauseEditorViewModel(
            pauseID: route.pauseID,
            draftID: route.draftID,
            repository: repository,
            selectionStore: selectionStore,
            routineEngine: routineEngine,
            pauseEngine: pauseEngine,
            usageDataService: usageDataService
        )
        pauseEditors[route.draftID] = created
        return created
    }

    func releaseRoutineEditor(draftID: UUID) {
        routineEditors.removeValue(forKey: draftID)
    }

    func releaseRuleEditor(draftID: UUID) {
        ruleEditors.removeValue(forKey: draftID)
    }

    func releasePauseEditor(draftID: UUID) {
        pauseEditors.removeValue(forKey: draftID)
    }

    func frictionEditor(
        route: FrictionEditorRoute,
        repository: FrictionRepository
    ) -> FrictionEditorViewModel {
        if let existing = frictionEditors[route.draftID] {
            return existing
        }

        let created = FrictionEditorViewModel(
            frictionID: route.frictionID,
            draftID: route.draftID,
            repository: repository
        )
        frictionEditors[route.draftID] = created
        return created
    }

    func releaseFrictionEditor(draftID: UUID) {
        frictionEditors.removeValue(forKey: draftID)
    }

    func appGroupEditor(
        route: AppGroupEditorRoute,
        repository: UserAppGroupRepository,
        selectionStore: ScreenTimeSelectionStore
    ) -> AppGroupEditorViewModel {
        if let existing = appGroupEditors[route.draftID] {
            return existing
        }

        let created = AppGroupEditorViewModel(
            appGroupID: route.appGroupID,
            draftID: route.draftID,
            repository: repository,
            selectionStore: selectionStore
        )
        appGroupEditors[route.draftID] = created
        return created
    }

    func releaseAppGroupEditor(draftID: UUID) {
        appGroupEditors.removeValue(forKey: draftID)
    }
}
