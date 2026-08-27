import Foundation

protocol PauseEventRepository {
    func events(from startDate: Date?, to endDate: Date?) async -> [PauseEvent]
    func save(_ event: PauseEvent) async
}
