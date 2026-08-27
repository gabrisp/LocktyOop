import Foundation

protocol PauseRuleRepository {
    func rules() async -> [PauseRule]
    func rule(id: UUID) async -> PauseRule?
    func rule(for appID: AppIdentity.ID) async -> PauseRule?
    func save(_ rule: PauseRule) async
    func delete(id: UUID) async
}
