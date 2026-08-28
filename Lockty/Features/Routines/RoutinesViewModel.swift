import Foundation
import Observation
import SwiftUI

@Observable
final class RoutinesViewModel {
    private let routineEngine: RoutineEngine
    private let repository: RoutineRepository
    private let shieldService: ShieldServicing
    private(set) var routines: [Routine] = []
    private(set) var errorMessage: String?

    init(routineEngine: RoutineEngine, repository: RoutineRepository, shieldService: ShieldServicing) {
        self.routineEngine = routineEngine
        self.repository = repository
        self.shieldService = shieldService
    }

    func load() async {
        do {
            let loaded = try await repository.routines()
            withAnimation(.smooth(duration: 0.28)) {
                routines = loaded
            }
        }
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

    func debugUnblockEverything() async {
        do {
            try await shieldService.clearAllRestrictions()
            errorMessage = nil
            print("DEBUG unblock everything completed.")
        } catch {
            errorMessage = error.localizedDescription
            print("DEBUG unblock everything failed: \(error.localizedDescription)")
        }
    }
}
