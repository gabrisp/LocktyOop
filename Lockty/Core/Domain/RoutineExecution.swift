import Foundation

nonisolated enum RoutineCompletionReason: String, Codable, Hashable {
    case manualStop
    case naturalCompletion
    case breakExpired
    case interrupted
    case restarted
}

nonisolated struct RoutineBreakRecord: Codable, Hashable, Identifiable {
    let id: UUID
    var startedAt: Date
    var endedAt: Date?
    var trigger: BreakTrigger

    init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date? = nil,
        trigger: BreakTrigger
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.trigger = trigger
    }
}

nonisolated struct RoutineExecution: Codable, Hashable, Identifiable {
    let id: UUID
    var routineID: UUID
    var routineName: String
    var startedAt: Date
    var endedAt: Date?
    var completionReason: RoutineCompletionReason?
    var taskCompletions: [RoutineTaskCompletion]
    var breakHistory: [RoutineBreakRecord]

    init(
        id: UUID = UUID(),
        routineID: UUID,
        routineName: String,
        startedAt: Date,
        endedAt: Date? = nil,
        completionReason: RoutineCompletionReason? = nil,
        taskCompletions: [RoutineTaskCompletion] = [],
        breakHistory: [RoutineBreakRecord] = []
    ) {
        self.id = id
        self.routineID = routineID
        self.routineName = routineName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.completionReason = completionReason
        self.taskCompletions = taskCompletions
        self.breakHistory = breakHistory
    }
}
