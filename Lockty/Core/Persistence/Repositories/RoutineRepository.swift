import Foundation

enum RoutineRepositoryError: LocalizedError {
    case unavailable
    case invalidData

    var errorDescription: String? {
        switch self {
        case .unavailable: "Local routine storage is unavailable."
        case .invalidData: "A saved routine could not be decoded."
        }
    }
}

protocol RoutineRepository {
    func routines() async throws -> [Routine]
    func save(_ routine: Routine) async throws
    func delete(id: UUID) async throws
}
