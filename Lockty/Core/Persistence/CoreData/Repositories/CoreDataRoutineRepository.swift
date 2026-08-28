import CoreData
import FamilyControls
import Foundation
import OSLog

private let routineRepositoryLogger = Logger(subsystem: "com.gabrisp.Lockty", category: "routines")

@MainActor
final class CoreDataRoutineRepository: RoutineRepository {
    private let controller: PersistenceController
    private let selectionStore: ScreenTimeSelectionStore
    private let mapper = RoutineMapper()

    init(controller: PersistenceController, selectionStore: ScreenTimeSelectionStore) {
        self.controller = controller
        self.selectionStore = selectionStore
    }

    func routines() async throws -> [Routine] {
        guard let context = controller.viewContext else { throw RoutineRepositoryError.unavailable }
        let request = RoutineEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \RoutineEntity.createdAt, ascending: true)]
        let entities = try context.fetch(request)
        print("Loaded routines from Core Data count=\(entities.count)")

        return try entities.map { entity in
            if let selection = try mapper.selection(from: entity) {
                try? selectionStore.save(selection, scope: .routine(entity.id))
            }
            return try mapper.makeDomain(from: entity)
        }
    }

    func save(_ routine: Routine) async throws {
        guard let context = controller.viewContext else { throw RoutineRepositoryError.unavailable }
        let selection = try? selectionStore.load(scope: .routine(routine.id))

        let request = RoutineEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", routine.id as CVarArg)
        request.fetchLimit = 1
        let entity = try context.fetch(request).first ?? RoutineEntity(context: context)

        try mapper.apply(routine, selection: selection, to: entity, context: context)
        try context.save()
        routineRepositoryLogger.notice("Saved routine id=\(routine.id.uuidString, privacy: .public) name=\(routine.name, privacy: .public) tasks=\(routine.tasks.count) apps=\(routine.blockedApplications.count) domains=\(routine.blockedDomains.count)")
        print("Saved routine id=\(routine.id.uuidString) name=\(routine.name) tasks=\(routine.tasks.count) apps=\(routine.blockedApplications.count) domains=\(routine.blockedDomains.count)")
    }

    func delete(id: UUID) async throws {
        guard let context = controller.viewContext else { throw RoutineRepositoryError.unavailable }
        let request = RoutineEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        if let entity = try context.fetch(request).first {
            context.delete(entity)
            try context.save()
            try? selectionStore.remove(scope: .routine(id))
            print("Deleted routine id=\(id.uuidString)")
        }
    }
}
