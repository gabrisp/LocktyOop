import Foundation
import SwiftData

protocol RoutineExecutionRepository {
    func executions(from startDate: Date?, to endDate: Date?) async throws -> [RoutineExecution]
    func execution(id: UUID) async throws -> RoutineExecution?
    func save(_ execution: RoutineExecution) async throws
}

@MainActor
final class SwiftDataRoutineExecutionRepository: RoutineExecutionRepository {
    private let store: PersistenceStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(store: PersistenceStore) {
        self.store = store
    }

    func executions(from startDate: Date?, to endDate: Date?) async throws -> [RoutineExecution] {
        guard let context = store.context else { return [] }
        let records = try context.fetch(FetchDescriptor<RoutineExecutionRecord>())
        return records.compactMap { makeExecution(from: $0) }
            .filter { execution in
                let afterStart = startDate.map { execution.startedAt >= $0 } ?? true
                let beforeEnd = endDate.map { execution.startedAt < $0 } ?? true
                return afterStart && beforeEnd
            }
            .sorted { $0.startedAt < $1.startedAt }
    }

    func execution(id: UUID) async throws -> RoutineExecution? {
        guard let context = store.context else { return nil }
        let descriptor = FetchDescriptor<RoutineExecutionRecord>(
            predicate: #Predicate { $0.id == id }
        )
        guard let record = try context.fetch(descriptor).first else { return nil }
        return makeExecution(from: record)
    }

    func save(_ execution: RoutineExecution) async throws {
        guard let context = store.context else { return }
        let descriptor = FetchDescriptor<RoutineExecutionRecord>(
            predicate: #Predicate { $0.id == execution.id }
        )

        let taskData = try encoder.encode(execution.taskCompletions)
        let breakData = try encoder.encode(execution.breakHistory)

        if let existing = try context.fetch(descriptor).first {
            existing.routineID = execution.routineID
            existing.routineName = execution.routineName
            existing.startedAt = execution.startedAt
            existing.endedAt = execution.endedAt
            existing.completionReasonRawValue = execution.completionReason?.rawValue
            existing.taskCompletionsData = taskData
            existing.breakHistoryData = breakData
        } else {
            context.insert(
                RoutineExecutionRecord(
                    id: execution.id,
                    routineID: execution.routineID,
                    routineName: execution.routineName,
                    startedAt: execution.startedAt,
                    endedAt: execution.endedAt,
                    completionReasonRawValue: execution.completionReason?.rawValue,
                    taskCompletionsData: taskData,
                    breakHistoryData: breakData
                )
            )
        }

        try context.save()
    }

    private func makeExecution(from record: RoutineExecutionRecord) -> RoutineExecution? {
        let taskCompletions = (try? decoder.decode([RoutineTaskCompletion].self, from: record.taskCompletionsData)) ?? []
        let breakHistory = (try? decoder.decode([RoutineBreakRecord].self, from: record.breakHistoryData)) ?? []
        let reason = record.completionReasonRawValue.flatMap(RoutineCompletionReason.init(rawValue:))
        return RoutineExecution(
            id: record.id,
            routineID: record.routineID,
            routineName: record.routineName,
            startedAt: record.startedAt,
            endedAt: record.endedAt,
            completionReason: reason,
            taskCompletions: taskCompletions,
            breakHistory: breakHistory
        )
    }
}
