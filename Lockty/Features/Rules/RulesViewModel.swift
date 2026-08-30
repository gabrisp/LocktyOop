import Combine
import FamilyControls
import Foundation
import ManagedSettings
import SwiftUI

final class RulesViewModel: ObservableObject {
    private let routineEngine: RoutineEngine
    private let repository: RuleRepository
    private let appGroupRepository: UserAppGroupRepository
    private let selectionStore: ScreenTimeSelectionStore

    @Published private(set) var rules: [Rule] = []
    @Published private(set) var applicationTokens: [UUID: [ApplicationToken]] = [:]
    @Published private(set) var errorMessage: String?

    init(
        routineEngine: RoutineEngine,
        repository: RuleRepository,
        appGroupRepository: UserAppGroupRepository,
        selectionStore: ScreenTimeSelectionStore
    ) {
        self.routineEngine = routineEngine
        self.repository = repository
        self.appGroupRepository = appGroupRepository
        self.selectionStore = selectionStore
    }

    func load() async {
        do {
            let loaded = try await repository.rules()
            let groups = await appGroupRepository.appGroups()
            let tokens = loaded.reduce(into: [UUID: [ApplicationToken]]()) { result, rule in
                let groupScopes = groups
                    .filter { rule.appGroupIDs.contains($0.id) }
                    .map { ScreenTimeSelectionScope.appGroup($0.id) }
                let primaryScope: ScreenTimeSelectionScope = rule.kind == .schedule ? .routine(rule.id) : .rule(rule.id)
                let merged = selectionStore.mergedSelection(scopes: Set([primaryScope] + groupScopes))
                result[rule.id] = merged.applicationTokens.stablePrefix(merged.applicationTokens.count)
            }
            withAnimation(.smooth(duration: 0.28)) {
                rules = loaded
                applicationTokens = tokens
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func tokens(for ruleID: UUID) -> [ApplicationToken] {
        applicationTokens[ruleID] ?? []
    }

    func activeScheduleRuleID() -> UUID? {
        routineEngine.activeRoutine()?.routineID
    }

    func delete(id: UUID) async {
        do {
            try await repository.delete(id: id)
            rules.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearError() {
        errorMessage = nil
    }
}
