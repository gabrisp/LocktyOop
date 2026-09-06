import FamilyControls
import Foundation
import ManagedSettings

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
    /// Re-registers the watch whenever what it watches changes.
    ///
    /// Here rather than at each call site: the distracting list is edited from the
    /// picker, from the usage breakdown and from Today, and a list that changes without
    /// the monitoring changing is a setting that silently does nothing.
    private let deviceActivityService: DeviceActivityServicing?

    init(
        repository: AutoFocusRepository,
        classificationRepository: AppClassificationRepository,
        selectionStore: ScreenTimeSelectionStore,
        deviceActivityService: DeviceActivityServicing? = nil
    ) {
        self.repository = repository
        self.classificationRepository = classificationRepository
        self.selectionStore = selectionStore
        self.deviceActivityService = deviceActivityService
    }

    /// Puts the current list and level in front of DeviceActivity again.
    func resync() async {
        guard let deviceActivityService else { return }
        do {
            try await deviceActivityService.syncAutoFocus(await repository.loadConfiguration())
        } catch {
            print("AutoFocus resync failed: \(error.localizedDescription)")
        }
    }

    func configuration() async -> AutoFocusConfiguration {
        await repository.loadConfiguration()
    }

    func saveConfiguration(_ configuration: AutoFocusConfiguration) async throws {
        try await repository.saveConfiguration(configuration)
        await resync()
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

        var configuration = await repository.loadConfiguration()
        configuration.distractingApplicationIDs = newIDs
        configuration.updatedAt = Date()
        try await repository.saveConfiguration(configuration)
        await resync()
    }

    /// Files an app in or out of the distracting list when it is reclassified.
    ///
    /// Takes the whole identity, not just its id, because the token is the part that
    /// matters and the id cannot be turned back into one. An app you called unproductive
    /// in the usage list has never been through a picker, so there is no saved selection
    /// holding its token to look it up in -- the lookup came back empty, the distracting
    /// selection stayed empty, and DeviceActivity was handed nothing to watch. The report
    /// the app was named in carries the token; this uses it.
    func updateMembership(for app: AppIdentity, classification: AppClassification) async {
        var configuration = await repository.loadConfiguration()
        var selection = distractingSelection()

        // The token from the identity if it has one, and the old lookup as the fallback
        // for identities that arrived without it.
        let tokens: Set<ApplicationToken> = app.applicationToken.map { [$0] }
            ?? selectionStore.applicationTokens(for: [app.id])

        if classification == .unproductive {
            configuration.distractingApplicationIDs.insert(app.id)
            selection.applicationTokens.formUnion(tokens)
        } else {
            configuration.distractingApplicationIDs.remove(app.id)
            selection.applicationTokens.subtract(tokens)
        }

        configuration.updatedAt = Date()
        try? selectionStore.save(selection, scope: .distracting)
        try? await repository.saveConfiguration(configuration)
        await resync()
    }
}
