import Combine
import FamilyControls
import Foundation
import ManagedSettings
import SwiftUI

final class RoutinesViewModel: ObservableObject {
    private let routineEngine: RoutineEngine
    private let repository: RoutineRepository
    private let shieldService: ShieldServicing
    private let scheduleCoordinator: RoutineScheduleCoordinator
    private let selectionStore: ScreenTimeSelectionStore
    @Published private(set) var routines: [Routine] = []
    /// Resolved once per load rather than read from the card's body: the tokens live in
    /// the selection store, and hitting it on every redraw would re-read the App Group
    /// for every tile on screen.
    @Published private(set) var applicationTokens: [UUID: [ApplicationToken]] = [:]
    @Published private(set) var errorMessage: String?

    init(
        routineEngine: RoutineEngine,
        repository: RoutineRepository,
        shieldService: ShieldServicing,
        scheduleCoordinator: RoutineScheduleCoordinator,
        selectionStore: ScreenTimeSelectionStore
    ) {
        self.scheduleCoordinator = scheduleCoordinator
        self.routineEngine = routineEngine
        self.repository = repository
        self.shieldService = shieldService
        self.selectionStore = selectionStore
    }

    func tokens(for routineID: UUID) -> [ApplicationToken] {
        applicationTokens[routineID] ?? []
    }

    func load() async {
        do {
            let loaded = try await repository.routines()
            let tokens = loaded.reduce(into: [UUID: [ApplicationToken]]()) { result, routine in
                let selection = (try? selectionStore.load(scope: .routine(routine.id)))?.applicationTokens ?? []
                result[routine.id] = selection.stablePrefix(selection.count)
            }
            withAnimation(.smooth(duration: 0.28)) {
                routines = loaded
                applicationTokens = tokens
            }
            // Keeps background scheduling in step with whatever was just created,
            // edited or deleted.
            await scheduleCoordinator.sync()
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
