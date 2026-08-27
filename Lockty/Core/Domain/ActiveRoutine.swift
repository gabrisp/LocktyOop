import Foundation

nonisolated struct ActiveRoutine: Codable, Hashable, Identifiable {
    let id: UUID
    var routineID: UUID
    var nameSnapshot: String
    var modeSnapshot: RoutineMode
    var startedAt: Date
    var expectedEndAt: Date?
    var trigger: RoutineTrigger
    var shieldPolicy: ShieldPolicy
    var breakPolicySnapshot: BreakPolicy
    var taskCompletions: [RoutineTaskCompletion]
    var allowsPauseDuringStrictMode: Bool

    init(
        id: UUID = UUID(),
        routineID: UUID,
        nameSnapshot: String,
        modeSnapshot: RoutineMode,
        startedAt: Date,
        expectedEndAt: Date? = nil,
        trigger: RoutineTrigger,
        shieldPolicy: ShieldPolicy,
        breakPolicySnapshot: BreakPolicy,
        taskCompletions: [RoutineTaskCompletion],
        allowsPauseDuringStrictMode: Bool
    ) {
        self.id = id
        self.routineID = routineID
        self.nameSnapshot = nameSnapshot
        self.modeSnapshot = modeSnapshot
        self.startedAt = startedAt
        self.expectedEndAt = expectedEndAt
        self.trigger = trigger
        self.shieldPolicy = shieldPolicy
        self.breakPolicySnapshot = breakPolicySnapshot
        self.taskCompletions = taskCompletions
        self.allowsPauseDuringStrictMode = allowsPauseDuringStrictMode
    }
}
