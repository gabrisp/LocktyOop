import CoreData
import Foundation

@MainActor
final class CoreDataAppClassificationRepository: AppClassificationRepository {
    private let controller: PersistenceController
    private let mapper = AppClassificationMapper()

    init(controller: PersistenceController) {
        self.controller = controller
    }

    func classification(for appID: AppIdentity.ID) async -> AppClassification? {
        guard let context = controller.viewContext else { return nil }
        let request = AppClassificationEntity.fetchRequest()
        request.predicate = NSPredicate(format: "appID == %@", appID.rawValue)
        request.fetchLimit = 1
        let savedClassification = (try? context.fetch(request).first).flatMap(mapper.makeDomain(from:))

        if let savedClassification, savedClassification != .neutral {
            return savedClassification
        }

        return AppClassificationHeuristics.classification(appID: appID) ?? savedClassification
    }

    func allClassifications() async -> [AppIdentity.ID: AppClassification] {
        guard let context = controller.viewContext,
              let entities = try? context.fetch(AppClassificationEntity.fetchRequest())
        else {
            return [:]
        }
        return entities.reduce(into: [:]) { partialResult, entity in
            guard let classification = mapper.makeDomain(from: entity) else { return }
            partialResult[AppIdentity.ID(rawValue: entity.appID)] = classification
        }
    }

    func saveClassification(_ classification: AppClassification, for appID: AppIdentity.ID) async {
        guard let context = controller.viewContext else { return }
        let request = AppClassificationEntity.fetchRequest()
        request.predicate = NSPredicate(format: "appID == %@", appID.rawValue)
        request.fetchLimit = 1
        let entity = (try? context.fetch(request))?.first ?? AppClassificationEntity(context: context)
        mapper.apply(appID: appID, classification: classification, to: entity)
        try? context.save()
    }
}
