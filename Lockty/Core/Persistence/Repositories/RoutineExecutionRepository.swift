import Foundation

protocol RoutineExecutionRepository {
    func executions(from startDate: Date?, to endDate: Date?) async throws -> [RoutineExecution]
    func execution(id: UUID) async throws -> RoutineExecution?
    func save(_ execution: RoutineExecution) async throws
}
