import Foundation
import SwiftData

@Model
final class RoutineExecutionRecord {
    @Attribute(.unique) var id: UUID
    var routineID: UUID
    var routineName: String
    var startedAt: Date
    var endedAt: Date?
    var completionReasonRawValue: String?
    var taskCompletionsData: Data
    var breakHistoryData: Data

    init(
        id: UUID,
        routineID: UUID,
        routineName: String,
        startedAt: Date,
        endedAt: Date? = nil,
        completionReasonRawValue: String? = nil,
        taskCompletionsData: Data = Data(),
        breakHistoryData: Data = Data()
    ) {
        self.id = id
        self.routineID = routineID
        self.routineName = routineName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.completionReasonRawValue = completionReasonRawValue
        self.taskCompletionsData = taskCompletionsData
        self.breakHistoryData = breakHistoryData
    }
}
