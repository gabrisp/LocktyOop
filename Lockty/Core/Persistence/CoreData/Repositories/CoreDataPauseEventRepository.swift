import CoreData
import Foundation
import OSLog

private let pauseEventRepositoryLogger = Logger(subsystem: "com.gabrisp.Lockty", category: "pauses")

@MainActor
final class CoreDataPauseEventRepository: PauseEventRepository {
    private let controller: PersistenceController
    private let mapper = PauseEventMapper()

    init(controller: PersistenceController) {
        self.controller = controller
    }

    func events(from startDate: Date?, to endDate: Date?) async -> [PauseEvent] {
        guard let context = controller.viewContext else { return [] }
        let request = PauseEventEntity.fetchRequest()
        var predicates: [NSPredicate] = []
        if let startDate { predicates.append(NSPredicate(format: "triggeredAt >= %@", startDate as NSDate)) }
        if let endDate { predicates.append(NSPredicate(format: "triggeredAt < %@", endDate as NSDate)) }
        if !predicates.isEmpty {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }
        guard let entities = try? context.fetch(request) else { return [] }
        return entities.compactMap { mapper.makeDomain(from: $0) }
    }

    func save(_ event: PauseEvent) async {
        guard let context = controller.viewContext else { return }
        let entity = PauseEventEntity(context: context)
        mapper.apply(event, to: entity)

        let ruleRequest = PauseRuleEntity.fetchRequest()
        ruleRequest.predicate = NSPredicate(format: "id == %@", event.pauseRuleID as CVarArg)
        ruleRequest.fetchLimit = 1
        entity.pauseRule = try? context.fetch(ruleRequest).first

        try? context.save()
        pauseEventRepositoryLogger.notice("Saved pause event id=\(event.id.uuidString, privacy: .public) app=\(event.application.displayName, privacy: .public) decision=\(event.decision.rawValue, privacy: .public)")
    }
}
