import FamilyControls
import Foundation

protocol UserAppGroupRepository {
    func appGroups() async -> [AppGroup]
    func appGroup(id: UUID) async -> AppGroup?
    func save(_ group: AppGroup) async throws
    func delete(id: UUID) async throws
}

protocol AutoFocusRepository {
    func loadConfiguration() async -> AutoFocusConfiguration
    func saveConfiguration(_ configuration: AutoFocusConfiguration) async throws
}

struct AppGroupStoreUserAppGroupRepository: UserAppGroupRepository {
    let appGroupStore: AppGroupStore

    func appGroups() async -> [AppGroup] {
        appGroupStore.loadUserAppGroups()
            .sorted { $0.createdAt < $1.createdAt }
    }

    func appGroup(id: UUID) async -> AppGroup? {
        appGroupStore.loadUserAppGroups().first(where: { $0.id == id })
    }

    func save(_ group: AppGroup) async throws {
        var groups = appGroupStore.loadUserAppGroups()
        if let index = groups.firstIndex(where: { $0.id == group.id }) {
            groups[index] = group
        } else {
            groups.append(group)
        }
        try appGroupStore.saveUserAppGroups(groups)
    }

    func delete(id: UUID) async throws {
        var groups = appGroupStore.loadUserAppGroups()
        groups.removeAll { $0.id == id }
        try appGroupStore.saveUserAppGroups(groups)
    }
}

struct AppGroupStoreAutoFocusRepository: AutoFocusRepository {
    let appGroupStore: AppGroupStore

    func loadConfiguration() async -> AutoFocusConfiguration {
        appGroupStore.loadAutoFocusConfiguration()
    }

    func saveConfiguration(_ configuration: AutoFocusConfiguration) async throws {
        try appGroupStore.saveAutoFocusConfiguration(configuration)
    }
}

@MainActor
final class AutoFocusManager {
    private let repository: AutoFocusRepository
    private let classificationRepository: AppClassificationRepository
    private let selectionStore: ScreenTimeSelectionStore

    init(
        repository: AutoFocusRepository,
        classificationRepository: AppClassificationRepository,
        selectionStore: ScreenTimeSelectionStore
    ) {
        self.repository = repository
        self.classificationRepository = classificationRepository
        self.selectionStore = selectionStore
    }

    func configuration() async -> AutoFocusConfiguration {
        await repository.loadConfiguration()
    }

    func saveConfiguration(_ configuration: AutoFocusConfiguration) async throws {
        try await repository.saveConfiguration(configuration)
    }

    func distractingSelection() -> FamilyActivitySelection {
        (try? selectionStore.load(scope: .distracting)) ?? FamilyActivitySelection()
    }

    func saveDistractingSelection(_ selection: FamilyActivitySelection) async throws {
        let previousSelection = distractingSelection()
        let previousIDs = Set(previousSelection.applicationTokens.map(AppIdentity.ID.init(token:)))
        let newIDs = Set(selection.applicationTokens.map(AppIdentity.ID.init(token:)))

        try selectionStore.save(selection, scope: .distracting)

        for added in newIDs.subtracting(previousIDs) {
            await classificationRepository.saveClassification(.unproductive, for: added)
        }

        for removed in previousIDs.subtracting(newIDs) {
            await classificationRepository.saveClassification(.neutral, for: removed)
        }

        var configuration = await repository.loadConfiguration()
        configuration.distractingApplicationIDs = newIDs
        configuration.updatedAt = Date()
        try await repository.saveConfiguration(configuration)
    }

    func updateMembership(for appID: AppIdentity.ID, classification: AppClassification) async {
        var configuration = await repository.loadConfiguration()
        var selection = distractingSelection()

        if classification == .unproductive {
            configuration.distractingApplicationIDs.insert(appID)
            let knownTokens = selectionStore.applicationTokens(for: [appID])
            selection.applicationTokens.formUnion(knownTokens)
        } else {
            configuration.distractingApplicationIDs.remove(appID)
            let knownTokens = selectionStore.applicationTokens(for: [appID])
            selection.applicationTokens.subtract(knownTokens)
        }

        configuration.updatedAt = Date()
        try? selectionStore.save(selection, scope: .distracting)
        try? await repository.saveConfiguration(configuration)
    }
}
