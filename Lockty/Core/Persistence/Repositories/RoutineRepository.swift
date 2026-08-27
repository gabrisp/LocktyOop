import Foundation
import SwiftData
import FamilyControls
import OSLog

private let routineRepositoryLogger = Logger(subsystem: "com.gabrisp.Lockty", category: "routines")

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

@MainActor
final class SwiftDataRoutineRepository: RoutineRepository {
    private let store: PersistenceStore
    private let selectionStore: ScreenTimeSelectionStore
    private let mapper = RoutineRecordMapper()

    init(
        store: PersistenceStore,
        selectionStore: ScreenTimeSelectionStore
    ) {
        self.store = store
        self.selectionStore = selectionStore
    }

    func routines() async throws -> [Routine] {
        guard let context = store.context else { throw RoutineRepositoryError.unavailable }
        let records = try context.fetch(FetchDescriptor<RoutineRecord>())
            .sorted { $0.createdAt < $1.createdAt }

        return try records.map { record in
            if let selection = try mapper.selection(from: record) {
                try? selectionStore.save(selection, scope: .routine(record.id))
            }
            return try mapper.makeDomain(from: record)
        }
    }

    func save(_ routine: Routine) async throws {
        guard let context = store.context else { throw RoutineRepositoryError.unavailable }
        let selection = try? selectionStore.load(scope: .routine(routine.id))
        let descriptor = FetchDescriptor<RoutineRecord>(predicate: #Predicate { $0.id == routine.id })
        if let existing = try context.fetch(descriptor).first {
            let record = try mapper.makeRecord(from: routine, selection: selection)
            existing.name = record.name
            existing.icon = record.icon
            existing.modeRawValue = record.modeRawValue
            existing.triggersData = record.triggersData
            existing.familyActivitySelectionData = record.familyActivitySelectionData
            existing.blockedApplicationIDsData = record.blockedApplicationIDsData
            existing.blockedDomainsData = record.blockedDomainsData
            existing.tasksData = record.tasksData
            existing.breakPolicyData = record.breakPolicyData
            existing.allowsPauseDuringStrictMode = record.allowsPauseDuringStrictMode
            existing.updatedAt = record.updatedAt
        } else {
            context.insert(try mapper.makeRecord(from: routine, selection: selection))
        }
        try context.save()
        routineRepositoryLogger.notice("Saved routine id=\(routine.id.uuidString, privacy: .public) name=\(routine.name, privacy: .public) tasks=\(routine.tasks.count) apps=\(routine.blockedApplications.count) domains=\(routine.blockedDomains.count)")
    }

    func delete(id: UUID) async throws {
        guard let context = store.context else { throw RoutineRepositoryError.unavailable }
        let descriptor = FetchDescriptor<RoutineRecord>(predicate: #Predicate { $0.id == id })
        if let record = try context.fetch(descriptor).first { context.delete(record); try context.save() }
    }
}
