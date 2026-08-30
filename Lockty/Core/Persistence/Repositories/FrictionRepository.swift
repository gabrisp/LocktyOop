import Foundation

protocol FrictionRepository {
    func frictions() async -> [Friction]
    func seedDefaultFrictionIfNeeded() async
    func friction(id: UUID) async -> Friction?
    func save(_ friction: Friction) async throws
    func delete(id: UUID) async throws
}

struct AppGroupFrictionRepository: FrictionRepository {
    private let pauseFlowRepository: PauseFlowRepository
    private let routineRepository: RoutineRepository
    private let appGroupStore: AppGroupStore

    init(
        pauseFlowRepository: PauseFlowRepository,
        routineRepository: RoutineRepository,
        appGroupStore: AppGroupStore
    ) {
        self.pauseFlowRepository = pauseFlowRepository
        self.routineRepository = routineRepository
        self.appGroupStore = appGroupStore
    }

    func frictions() async -> [Friction] {
        await pauseFlowRepository.flows().map(Friction.init(flow:))
    }

    func seedDefaultFrictionIfNeeded() async {
        await pauseFlowRepository.seedDefaultFlowIfNeeded()
    }

    func friction(id: UUID) async -> Friction? {
        await pauseFlowRepository.flow(id: id).map(Friction.init(flow:))
    }

    func save(_ friction: Friction) async throws {
        let flow = friction.flow
        try await pauseFlowRepository.save(flow)
        let updatedRoutineIDs = try await syncReferencedRoutines(with: flow)
        try syncActiveRoutineSnapshotIfNeeded(routineIDs: updatedRoutineIDs, flow: flow)
    }

    func delete(id: UUID) async throws {
        try await pauseFlowRepository.delete(id: id)
    }

    private func syncReferencedRoutines(with flow: PauseFlow) async throws -> Set<UUID> {
        let routines = try await routineRepository.routines()
        let matching = routines.filter { $0.pauseFlowID == flow.id }

        for var routine in matching {
            routine.pausePolicy = flow.policy
            routine.updatedAt = Date()
            try await routineRepository.save(routine)
        }

        return Set(matching.map(\.id))
    }

    private func syncActiveRoutineSnapshotIfNeeded(routineIDs: Set<UUID>, flow: PauseFlow) throws {
        guard !routineIDs.isEmpty else { return }
        try appGroupStore.updateRuntimeState { state in
            guard let activeRoutine = state.activeRoutine, routineIDs.contains(activeRoutine.routineID) else { return }
            state.activeRoutine?.pausePolicySnapshot = flow.policy
        }
    }
}
