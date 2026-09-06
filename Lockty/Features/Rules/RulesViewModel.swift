import Combine
import FamilyControls
import Foundation
import ManagedSettings
import SwiftUI

@MainActor
final class RulesViewModel: ObservableObject {
    private let routineEngine: RoutineEngine
    private let pauseEngine: PauseEngine
    private let repository: RuleRepository
    private let appGroupRepository: UserAppGroupRepository
    private let scheduleCoordinator: RoutineScheduleCoordinator
    private let selectionStore: ScreenTimeSelectionStore
    private let appGroupStore: AppGroupStore

    @Published private(set) var rules: [Rule] = []
    @Published private(set) var applicationTokens: [UUID: [ApplicationToken]] = [:]
    /// Which rules are on hold and until when, read with them.
    @Published private(set) var pauses: RulePauseState = RulePauseState()
    @Published private(set) var errorMessage: String?

    init(
        routineEngine: RoutineEngine,
        pauseEngine: PauseEngine,
        repository: RuleRepository,
        appGroupRepository: UserAppGroupRepository,
        scheduleCoordinator: RoutineScheduleCoordinator,
        selectionStore: ScreenTimeSelectionStore,
        appGroupStore: AppGroupStore
    ) {
        self.routineEngine = routineEngine
        self.pauseEngine = pauseEngine
        self.repository = repository
        self.appGroupRepository = appGroupRepository
        self.scheduleCoordinator = scheduleCoordinator
        self.selectionStore = selectionStore
        self.appGroupStore = appGroupStore
    }

    func load() async {
        do {
            let loaded = try await repository.rules()
            let tokens = loaded.reduce(into: [UUID: [ApplicationToken]]()) { result, rule in
                let groupScopes = rule.appGroupIDs.map(ScreenTimeSelectionScope.appGroupScope)
                let primaryScope: ScreenTimeSelectionScope = rule.kind == .schedule ? .routine(rule.id) : .rule(rule.id)
                let merged = selectionStore.mergedSelection(scopes: Set([primaryScope] + groupScopes))
                result[rule.id] = merged.applicationTokens.stablePrefix(merged.applicationTokens.count)
            }
            let pauseState = appGroupStore.loadRulePauseState()
            withAnimation(.smooth(duration: 0.28)) {
                rules = loaded
                applicationTokens = tokens
                pauses = pauseState
            }
            // Keeps DeviceActivity monitoring in step with whatever was just created,
            // edited or deleted. This used to hang off RoutinesViewModel, which nothing
            // reaches any more -- the list of routines lives here now, so the sync does
            // too, and without it no scheduled routine was ever registered to start.
            await stopPausedRoutines(in: loaded)
            await scheduleCoordinator.sync()
            // And the shield itself. A limit rule is not a routine: nothing starts or
            // stops, so nothing was recomputing the policy after one was created, edited
            // or switched on -- an open-count rule stayed unenforced until the next cold
            // launch, which is the only other place this is done.
            await pauseEngine.refreshShields()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Ends any routine that is running while its rule is on hold.
    ///
    /// Putting a schedule on hold is done from the editor, which knows nothing about what
    /// is currently running -- and a hold that leaves the routine you just paused still
    /// blocking your apps is not a pause. The extension refuses to *start* a paused
    /// routine; this is the other half, for one that had already begun.
    private func stopPausedRoutines(in rules: [Rule]) async {
        let pauses = appGroupStore.loadRulePauseState()
        guard !pauses.pausedUntil.isEmpty else { return }

        for rule in rules where rule.kind == .schedule && pauses.isPaused(rule.id) {
            guard routineEngine.isRunning(rule.id) else { continue }
            await routineEngine.stop(routineID: rule.id)
        }
    }

    func pauseState() -> RulePauseState {
        appGroupStore.loadRulePauseState()
    }

    func tokens(for ruleID: UUID) -> [ApplicationToken] {
        applicationTokens[ruleID] ?? []
    }

    /// When the hold on a rule ends, or nil when it is not on hold.
    func pausedUntil(for ruleID: UUID) -> Date? {
        pauses.pauseEnd(for: ruleID)
    }

    /// Every schedule rule running right now. A set, not one id: routines overlap, so
    /// asking for "the" active one marked at most one card as running while several were.
    func activeScheduleRuleIDs() -> Set<UUID> {
        Set(routineEngine.activeRoutines.map(\.routineID))
    }

    func delete(id: UUID) async {
        do {
            try await repository.delete(id: id)
            rules.removeAll { $0.id == id }
            // A deleted rule stops blocking now, not on the next launch.
            await scheduleCoordinator.syncRules()
            await pauseEngine.refreshShields()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearError() {
        errorMessage = nil
    }
}
