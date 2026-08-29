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
    var pausePolicy: RoutinePausePolicy
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
        pausePolicy = routine.pausePolicy
        allowsPauseDuringStrictMode = routine.allowsPauseDuringStrictMode
        self.schedule = schedule
    }

    // Same tolerance as ActiveRoutine: snapshots written before pausePolicy existed must
    // still decode, or every scheduled routine stops starting.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        mode = try container.decode(RoutineMode.self, forKey: .mode)
        blockedApplications = try container.decode(Set<AppIdentity.ID>.self, forKey: .blockedApplications)
        blockedDomains = try container.decode(Set<String>.self, forKey: .blockedDomains)
        breakPolicy = try container.decode(BreakPolicy.self, forKey: .breakPolicy)
        pausePolicy = try container.decodeIfPresent(RoutinePausePolicy.self, forKey: .pausePolicy) ?? .off
        allowsPauseDuringStrictMode = try container.decode(Bool.self, forKey: .allowsPauseDuringStrictMode)
        schedule = try container.decode(RoutineSchedule.self, forKey: .schedule)
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
                reason: .routine(id),
                selectionScopes: [.routine(id)]
            ),
            breakPolicySnapshot: breakPolicy,
            pausePolicySnapshot: pausePolicy,
            taskCompletions: [],
            allowsPauseDuringStrictMode: allowsPauseDuringStrictMode
        )
    }
}
