import CoreData
import FamilyControls
import Foundation
import OSLog

private let pauseRepositoryLogger = Logger(subsystem: "com.gabrisp.Lockty", category: "pauses")

enum PauseRuleRepositoryError: LocalizedError {
    case unavailable
    case saveFailed(String)
    case deleteFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Pause storage is unavailable."
        case .saveFailed(let message):
            "Could not save Pause: \(message)"
        case .deleteFailed(let message):
            "Could not delete Pause: \(message)"
        }
    }
}

@MainActor
final class CoreDataPauseRuleRepository: PauseRuleRepository {
    private let controller: PersistenceController
    private let appGroupStore: AppGroupStore
    private let selectionStore: ScreenTimeSelectionStore
    private let mapper = PauseRuleMapper()

    init(
        controller: PersistenceController,
        appGroupStore: AppGroupStore = AppGroupStore(),
        selectionStore: ScreenTimeSelectionStore = ScreenTimeSelectionStore()
    ) {
        self.controller = controller
        self.appGroupStore = appGroupStore
        self.selectionStore = selectionStore
    }

    func rules() async -> [PauseRule] {
        guard let context = controller.viewContext else { return [] }
        guard let entities = try? context.fetch(PauseRuleEntity.fetchRequest()) else { return [] }
        print("Loaded pause rules from Core Data count=\(entities.count)")
        return entities.compactMap { entity in
            guard let domain = try? mapper.makeDomain(from: entity) else { return nil }
            syncSelectionStore(for: domain, entity: entity)
            return domain
        }.sorted { $0.application.displayName < $1.application.displayName }
    }

    func rule(id: UUID) async -> PauseRule? {
        guard let context = controller.viewContext else { return nil }
        let request = PauseRuleEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        guard let entity = try? context.fetch(request).first, let rule = try? mapper.makeDomain(from: entity) else {
            return nil
        }
        syncSelectionStore(for: rule, entity: entity)
        return rule
    }

    func rule(for appID: AppIdentity.ID) async -> PauseRule? {
        guard let context = controller.viewContext else { return nil }
        let request = PauseRuleEntity.fetchRequest()
        request.predicate = NSPredicate(format: "appID == %@", appID.rawValue)
        request.fetchLimit = 1
        guard let entity = try? context.fetch(request).first, let rule = try? mapper.makeDomain(from: entity) else {
            return nil
        }
        syncSelectionStore(for: rule, entity: entity)
        return rule
    }

    func save(_ rule: PauseRule) async throws {
        guard let context = controller.viewContext else { throw PauseRuleRepositoryError.unavailable }
        let request = PauseRuleEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", rule.id as CVarArg)
        request.fetchLimit = 1
        let entity = (try? context.fetch(request))?.first ?? PauseRuleEntity(context: context)

        do {
            try mapper.apply(rule, to: entity, context: context)
            try context.save()
        } catch {
            pauseRepositoryLogger.error("Failed saving pause rule id=\(rule.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            print("Failed saving pause rule id=\(rule.id.uuidString): \(error.localizedDescription)")
            throw PauseRuleRepositoryError.saveFailed(error.localizedDescription)
        }

        pauseRepositoryLogger.notice("Saved pause rule id=\(rule.id.uuidString, privacy: .public) app=\(rule.application.displayName, privacy: .public) steps=\(rule.steps.count)")
        print("Saved pause rule id=\(rule.id.uuidString) app=\(rule.application.displayName) steps=\(rule.steps.count)")
        syncSelectionStore(for: rule, entity: entity)
        syncSharedSnapshots()
    }

    func delete(id: UUID) async throws {
        guard let context = controller.viewContext else { throw PauseRuleRepositoryError.unavailable }
        let request = PauseRuleEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        if let entity = try? context.fetch(request).first {
            context.delete(entity)
            do {
                try context.save()
            } catch {
                pauseRepositoryLogger.error("Failed deleting pause rule id=\(id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
                print("Failed deleting pause rule id=\(id.uuidString): \(error.localizedDescription)")
                throw PauseRuleRepositoryError.deleteFailed(error.localizedDescription)
            }
            try? selectionStore.remove(scope: .pause(id))
            print("Deleted pause rule id=\(id.uuidString)")
            syncSharedSnapshots()
        }
    }

    private func syncSharedSnapshots() {
        let snapshots = appGroupStore.loadPauseRuleSnapshots()
        let currentRules = snapshotsByReloading()
        if snapshots != currentRules {
            try? appGroupStore.savePauseRuleSnapshots(currentRules)
        }
    }

    private func snapshotsByReloading() -> [PauseRuleSnapshot] {
        guard let context = controller.viewContext, let entities = try? context.fetch(PauseRuleEntity.fetchRequest()) else {
            return []
        }
        return entities.compactMap { entity in
            guard let domain = try? mapper.makeDomain(from: entity) else { return nil }
            return PauseRuleSnapshot(rule: domain)
        }
        .sorted { $0.application.displayName.localizedCaseInsensitiveCompare($1.application.displayName) == .orderedAscending }
    }

    private func syncSelectionStore(for rule: PauseRule, entity: PauseRuleEntity) {
        if let selection = try? mapper.selection(from: entity) {
            try? selectionStore.save(selection, scope: .pause(rule.id))
            print("Synced pause selection from entity ruleID=\(rule.id.uuidString) apps=\(selection.applicationTokens.count)")
            return
        }

        guard let token = rule.application.applicationToken else { return }
        var selection = FamilyActivitySelection()
        selection.applicationTokens = [token]
        try? selectionStore.save(selection, scope: .pause(rule.id))
        print("Synced reconstructed pause selection ruleID=\(rule.id.uuidString)")
    }
}
