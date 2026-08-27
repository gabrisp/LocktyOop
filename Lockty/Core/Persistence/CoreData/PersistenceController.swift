import CoreData
import Foundation

enum PersistenceControllerError: LocalizedError {
    case modelNotFound

    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            "The Lockty Core Data model could not be located."
        }
    }
}

@MainActor
final class PersistenceController {
    nonisolated private static let modelName = "Lockty"

    let container: NSPersistentContainer?
    private(set) var initializationError: Error?

    init(inMemory: Bool = false, model: NSManagedObjectModel? = PersistenceController.loadModel()) {
        guard let model else {
            container = nil
            initializationError = PersistenceControllerError.modelNotFound
            return
        }

        let container = NSPersistentContainer(name: Self.modelName, managedObjectModel: model)
        if let description = container.persistentStoreDescriptions.first {
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
            if inMemory {
                description.type = NSInMemoryStoreType
            }
        }

        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }

        if let loadError {
            self.container = nil
            initializationError = loadError
        } else {
            container.viewContext.automaticallyMergesChangesFromParent = true
            container.viewContext.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
            self.container = container
        }
    }

    var viewContext: NSManagedObjectContext? { container?.viewContext }

    func newBackgroundContext() -> NSManagedObjectContext? {
        container?.newBackgroundContext()
    }

    nonisolated private static func loadModel() -> NSManagedObjectModel? {
        let candidates: [Bundle] = [Bundle(for: PersistenceController.self), .main] + Bundle.allBundles
        for bundle in candidates {
            if let url = bundle.url(forResource: modelName, withExtension: "momd"),
               let model = NSManagedObjectModel(contentsOf: url) {
                return model
            }
        }
        return nil
    }
}
