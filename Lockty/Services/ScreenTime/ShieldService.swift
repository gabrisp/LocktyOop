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
    func clearAllRestrictions() async throws
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
        var selection = try selectionStore.selection(for: policy)
        let blockedDomains = Set(policy.blockedDomains.map(ManagedSettings.WebDomain.init(domain:)))
        guard !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty || !selection.webDomainTokens.isEmpty || !blockedDomains.isEmpty else {
            print("Shield apply failed because no selection matched policy reason=\(String(describing: policy.reason)) blockedApps=\(policy.blockedApplications.count) blockedDomains=\(policy.blockedDomains.count)")
            throw ShieldServiceError.selectionNotConfigured
        }

        // A pause allowance releases an app that the selection behind this policy still
        // lists -- and may only block through a category, where dropping the token does
        // nothing. Subtract it from the tokens and hand it to the category shield as an
        // exception, or "Continue" leaves the app shielded.
        let exemptTokens = selectionStore.applicationTokens(for: policy.exemptApplications)
        selection.applicationTokens.subtract(exemptTokens)

        print(
            """
            Applying shield policy reason=\(String(describing: policy.reason)) \
            apps=\(selection.applicationTokens.count) \
            categories=\(selection.categoryTokens.count) \
            selectionDomains=\(selection.webDomainTokens.count) \
            manualDomains=\(blockedDomains.count) \
            exempt=\(exemptTokens.count)
            """
        )
        managedSettingsStore.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        managedSettingsStore.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        managedSettingsStore.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens, except: exemptTokens)
        managedSettingsStore.webContent.blockedByFilter = blockedDomains.isEmpty ? nil : .specific(blockedDomains)
        try appGroupStore.updateRuntimeState { state in state.shieldPolicy = policy }
    }

    func remove(_ policy: ShieldPolicy) async throws {
        print("Removing shield policy reason=\(String(describing: policy.reason))")
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
        if !state.shieldPolicy.blocksNothing { try await apply(state.shieldPolicy) }
    }

    func clearAllRestrictions() async throws {
        managedSettingsStore.shield.applications = nil
        managedSettingsStore.shield.webDomains = nil
        managedSettingsStore.shield.applicationCategories = nil
        managedSettingsStore.webContent.blockedByFilter = nil
        try appGroupStore.saveRuntimeState(.empty)
        print("Cleared all ManagedSettings restrictions and reset runtime state.")
    }
}
