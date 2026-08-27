import CoreData
import Foundation

@MainActor
final class CoreDataRoutineExecutionRepository: RoutineExecutionRepository {
    private let controller: PersistenceController
    private let mapper = RoutineExecutionMapper()

    init(controller: PersistenceController) {
        self.controller = controller
    }

    func executions(from startDate: Date?, to endDate: Date?) async throws -> [RoutineExecution] {
        guard let context = controller.viewContext else { return [] }
        let request = RoutineExecutionEntity.fetchRequest()
        var predicates: [NSPredicate] = []
        if let startDate { predicates.append(NSPredicate(format: "startedAt >= %@", startDate as NSDate)) }
        if let endDate { predicates.append(NSPredicate(format: "startedAt < %@", endDate as NSDate)) }
        if !predicates.isEmpty {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }
        request.sortDescriptors = [NSSortDescriptor(keyPath: \RoutineExecutionEntity.startedAt, ascending: true)]
        let entities = try context.fetch(request)
        return entities.map { mapper.makeDomain(from: $0) }
    }

    func execution(id: UUID) async throws -> RoutineExecution? {
        guard let context = controller.viewContext else { return nil }
        let request = RoutineExecutionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        guard let entity = try context.fetch(request).first else { return nil }
        return mapper.makeDomain(from: entity)
    }

    func save(_ execution: RoutineExecution) async throws {
        guard let context = controller.viewContext else { return }
        let request = RoutineExecutionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", execution.id as CVarArg)
        request.fetchLimit = 1
        let entity = try context.fetch(request).first ?? RoutineExecutionEntity(context: context)
        mapper.apply(execution, to: entity, context: context)

        if entity.routine == nil {
            let routineRequest = RoutineEntity.fetchRequest()
            routineRequest.predicate = NSPredicate(format: "id == %@", execution.routineID as CVarArg)
            routineRequest.fetchLimit = 1
            entity.routine = try? context.fetch(routineRequest).first
        }

        try context.save()
    }
}
