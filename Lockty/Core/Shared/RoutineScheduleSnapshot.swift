import Foundation

/// Everything the DeviceActivity monitor extension needs to start a scheduled routine
/// on its own, with the app not running. The extension can't reach Core Data, so the
/// app mirrors each scheduled routine here whenever routines change.
nonisolated struct RoutineScheduleSnapshot: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var icon: String?
    var mode: RoutineMode
    var blockedApplications: Set<AppIdentity.ID>
    var blockedDomains: Set<String>
    var breakPolicy: BreakPolicy
    var allowsPauseDuringStrictMode: Bool
    var schedule: RoutineSchedule

    init(routine: Routine, schedule: RoutineSchedule) {
        id = routine.id
        name = routine.name
        icon = routine.icon
        mode = routine.mode
        blockedApplications = routine.blockedApplications
        blockedDomains = routine.blockedDomains
        breakPolicy = routine.breakPolicy
        allowsPauseDuringStrictMode = routine.allowsPauseDuringStrictMode
        self.schedule = schedule
    }

    /// The ActiveRoutine to write into runtime state when the interval starts.
    func makeActiveRoutine(startedAt: Date) -> ActiveRoutine {
        ActiveRoutine(
            routineID: id,
            nameSnapshot: name,
            iconSnapshot: icon,
            modeSnapshot: mode,
            startedAt: startedAt,
            trigger: .schedule(schedule),
            shieldPolicy: ShieldPolicy(
                blockedApplications: blockedApplications,
                blockedDomains: blockedDomains,
                reason: .routine(id)
            ),
            breakPolicySnapshot: breakPolicy,
            taskCompletions: [],
            allowsPauseDuringStrictMode: allowsPauseDuringStrictMode
        )
    }
}
