import Foundation

protocol RuleRepository {
    func rules() async throws -> [Rule]
    func rule(id: UUID) async throws -> Rule?
    func save(_ rule: Rule) async throws
    func delete(id: UUID) async throws
}

struct HybridRuleRepository: RuleRepository {
    let routineRepository: RoutineRepository
    let appGroupStore: AppGroupStore

    func rules() async throws -> [Rule] {
        let scheduleRules = try await routineRepository.routines().map(Rule.init(routine:))
        let storedRules = appGroupStore.loadStoredRules()
        return (scheduleRules + storedRules).sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    func rule(id: UUID) async throws -> Rule? {
        if let routine = try await routineRepository.routines().first(where: { $0.id == id }) {
            return Rule(routine: routine)
        }
        return appGroupStore.loadStoredRules().first(where: { $0.id == id })
    }

    func save(_ rule: Rule) async throws {
        if let routine = rule.routineBridge {
            try await routineRepository.save(routine)
            return
        }

        var storedRules = appGroupStore.loadStoredRules()
        if let index = storedRules.firstIndex(where: { $0.id == rule.id }) {
            storedRules[index] = rule
        } else {
            storedRules.append(rule)
        }
        try appGroupStore.saveStoredRules(storedRules)
    }

    func delete(id: UUID) async throws {
        if try await routineRepository.routines().contains(where: { $0.id == id }) {
            try await routineRepository.delete(id: id)
        }

        var storedRules = appGroupStore.loadStoredRules()
        storedRules.removeAll { $0.id == id }
        try appGroupStore.saveStoredRules(storedRules)
    }
}
