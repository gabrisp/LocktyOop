import Foundation
import FamilyControls
import ManagedSettings

enum ShieldServiceError: LocalizedError {
    case authorizationUnavailable
    case policyUnavailable
    case selectionNotConfigured

    var errorDescription: String? {
        switch self {
        case .authorizationUnavailable:
            "Screen Time authorization is not available."
        case .policyUnavailable:
            "No shield policy is available."
        case .selectionNotConfigured:
            "No Family Controls selection has been configured for this policy."
        }
    }
}

protocol ShieldServicing {
    func apply(_ policy: ShieldPolicy) async throws
    func remove(_ policy: ShieldPolicy) async throws
    func restoreFromRuntimeState() async throws
}

final class LiveShieldService: ShieldServicing {
    private let appGroupStore: AppGroupStore
    private let selectionStore: ScreenTimeSelectionStore
    private let managedSettingsStore = ManagedSettingsStore(named: ManagedSettingsStore.Name("lockty"))

    init(appGroupStore: AppGroupStore, selectionStore: ScreenTimeSelectionStore = ScreenTimeSelectionStore()) {
        self.appGroupStore = appGroupStore
        self.selectionStore = selectionStore
    }

    func apply(_ policy: ShieldPolicy) async throws {
        let selection = try selectionStore.selection(for: policy)
        let blockedDomains = Set(policy.blockedDomains.map(ManagedSettings.WebDomain.init(domain:)))
        guard !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty || !selection.webDomainTokens.isEmpty || !blockedDomains.isEmpty else {
            throw ShieldServiceError.selectionNotConfigured
        }
        managedSettingsStore.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        managedSettingsStore.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        managedSettingsStore.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        managedSettingsStore.webContent.blockedByFilter = blockedDomains.isEmpty ? nil : .specific(blockedDomains)
        try appGroupStore.updateRuntimeState { state in state.shieldPolicy = policy }
    }

    func remove(_ policy: ShieldPolicy) async throws {
        managedSettingsStore.shield.applications = nil
        managedSettingsStore.shield.webDomains = nil
        managedSettingsStore.shield.applicationCategories = nil
        managedSettingsStore.webContent.blockedByFilter = nil
        try appGroupStore.updateRuntimeState { state in
            if state.shieldPolicy == policy { state.shieldPolicy = .empty }
        }
    }

    func restoreFromRuntimeState() async throws {
        let state = try appGroupStore.loadRuntimeState()
        if state.shieldPolicy != .empty { try await apply(state.shieldPolicy) }
    }
}
