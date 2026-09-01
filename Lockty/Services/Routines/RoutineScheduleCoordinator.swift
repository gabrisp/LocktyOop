import Foundation

/// Keeps the DeviceActivity monitoring and the App Group snapshots in step with the
/// stored routines, so a scheduled routine can start with the app not running.
///
/// The monitor extension can't reach Core Data, so every scheduled routine is mirrored
/// into the App Group as a RoutineScheduleSnapshot whenever routines change.
@MainActor
struct RoutineScheduleCoordinator {
    private let repository: RoutineRepository
    private let appGroupStore: AppGroupStore
    private let deviceActivityService: DeviceActivityServicing

    init(
        repository: RoutineRepository,
        appGroupStore: AppGroupStore,
        deviceActivityService: DeviceActivityServicing
    ) {
        self.repository = repository
        self.appGroupStore = appGroupStore
        self.deviceActivityService = deviceActivityService
    }

    /// Registers the daily budget of every usage-limited rule, and drops the counters of
    /// rules that are gone.
    ///
    /// Separate from the routine sync above only because the two read different stores;
    /// `sync()` calls both, so nothing has to remember to call this one on its own.
    func syncRules() async {
        let rules = appGroupStore.loadStoredRules()

        var enforcement = appGroupStore.loadRuleEnforcementState()
        enforcement.prune(keeping: Set(rules.map(\.id)))
        try? appGroupStore.saveRuleEnforcementState(enforcement)

        do {
            try await deviceActivityService.syncRuleSchedules(rules)
            print("Synced \(rules.count) rule(s) for background enforcement")
        } catch {
            print("Rule schedule sync failed: \(error.localizedDescription)")
        }
    }

    func sync() async {
        await syncRules()

        guard let routines = try? await repository.routines() else { return }

        let snapshots: [RoutineScheduleSnapshot] = routines.compactMap { routine in
            for trigger in routine.triggers {
                if case .schedule(let schedule) = trigger, !schedule.weekdays.isEmpty {
                    return RoutineScheduleSnapshot(routine: routine, schedule: schedule)
                }
            }
            return nil
        }

        do {
            try appGroupStore.saveRoutineScheduleSnapshots(snapshots)
            try await deviceActivityService.syncRoutineSchedules(snapshots)
            print("Synced \(snapshots.count) scheduled routine(s) for background start")
        } catch {
            print("Routine schedule sync failed: \(error.localizedDescription)")
        }
    }
}
