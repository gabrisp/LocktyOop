import Foundation

protocol PauseFlowRepository {
    func flows() async -> [PauseFlow]
    func flow(id: UUID) async -> PauseFlow?
    func save(_ flow: PauseFlow) async throws
    func delete(id: UUID) async throws
}

/// Flows are kept in the App Group alongside the other shared state.
///
/// Not Core Data: they are small, the extensions read them as often as the app does, and
/// an entity means a model version. The same reasoning already puts routine schedules
/// and pause snapshots here. Worth moving when the model is next revised.
struct AppGroupPauseFlowRepository: PauseFlowRepository {
    private let appGroupStore: AppGroupStore

    init(appGroupStore: AppGroupStore) {
        self.appGroupStore = appGroupStore
    }

    func flows() async -> [PauseFlow] {
        appGroupStore.loadPauseFlows().sorted { $0.createdAt < $1.createdAt }
    }

    func flow(id: UUID) async -> PauseFlow? {
        appGroupStore.loadPauseFlows().first { $0.id == id }
    }

    func save(_ flow: PauseFlow) async throws {
        var stored = appGroupStore.loadPauseFlows()
        if let index = stored.firstIndex(where: { $0.id == flow.id }) {
            stored[index] = flow
        } else {
            stored.append(flow)
        }
        try appGroupStore.savePauseFlows(stored)
    }

    func delete(id: UUID) async throws {
        var stored = appGroupStore.loadPauseFlows()
        stored.removeAll { $0.id == id }
        try appGroupStore.savePauseFlows(stored)
    }
}
