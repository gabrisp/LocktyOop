import Foundation

protocol PauseRuleRepository {
    func rules() async -> [PauseRule]
    func rule(id: UUID) async -> PauseRule?
    func rule(for appID: AppIdentity.ID) async -> PauseRule?
    func save(_ rule: PauseRule) async
    func delete(id: UUID) async
}

actor InMemoryPauseRuleRepository: PauseRuleRepository {
    private var storage: [UUID: PauseRule]

    init(rules: [PauseRule]) {
        storage = Dictionary(uniqueKeysWithValues: rules.map { ($0.id, $0) })
    }

    func rules() async -> [PauseRule] {
        storage.values.sorted { $0.application.displayName < $1.application.displayName }
    }

    func rule(id: UUID) async -> PauseRule? {
        storage[id]
    }

    func rule(for appID: AppIdentity.ID) async -> PauseRule? {
        storage.values.first(where: { $0.application.id == appID })
    }

    func save(_ rule: PauseRule) async {
        storage[rule.id] = rule
    }

    func delete(id: UUID) async {
        storage[id] = nil
    }
}
