import Foundation
import Observation

@Observable
final class RoutinesViewModel {
    private let routineEngine: RoutineEngine
    private let repository: RoutineRepository
    private(set) var routines: [Routine] = []
    private(set) var errorMessage: String?

    init(routineEngine: RoutineEngine, repository: RoutineRepository) {
        self.routineEngine = routineEngine
        self.repository = repository
    }

    func load() async {
        do { routines = try await repository.routines() }
        catch { errorMessage = error.localizedDescription }
    }

    func start(_ routine: Routine) async {
        await routineEngine.start(routine)
        if case .failed(let message) = routineEngine.state {
            errorMessage = message
        } else {
            errorMessage = nil
        }
    }

    func activeRoutineID() -> UUID? {
        routineEngine.activeRoutine()?.routineID
    }

    func delete(id: UUID) async {
        let decision = StrictModePolicy().decision(for: .deleteRoutine, activeRoutine: routineEngine.activeRoutine())
        guard routineEngine.activeRoutine()?.routineID != id || decision.isAllowed else {
            errorMessage = decision.reason
            return
        }

        do {
            try await repository.delete(id: id)
            routines.removeAll { $0.id == id }
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    func clearError() {
        errorMessage = nil
    }
}
