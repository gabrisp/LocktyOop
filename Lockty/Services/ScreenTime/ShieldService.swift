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
        let restrictions = policy.contentRestrictions
        let guards = policy.strictGuards
        guard !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty || !selection.webDomainTokens.isEmpty || !blockedDomains.isEmpty || !restrictions.isEmpty || !guards.isEmpty else {
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
        // `.specific` is an *allow* list: `.specific(blockedDomains)` said "let this
        // routine's blocked sites through and nothing else", so adding one domain to a
        // routine shut off the entire web. `.auto(_:)` is the one that takes a set of
        // domains to block. It also switches on Apple's adult-content filter, which is
        // why the two travel together here -- iOS has no way to block named sites without
        // it, so a routine with sites listed gets the filter whether or not it asked.
        managedSettingsStore.webContent.blockedByFilter = webContentFilter(
            blocking: blockedDomains,
            restrictions: restrictions
        )
        managedSettingsStore.appStore.denyInAppPurchases = restrictions.blocksITunesPurchases ? true : nil
        managedSettingsStore.appStore.requirePasswordForPurchases = restrictions.blocksITunesPurchases ? true : nil
        managedSettingsStore.application.denyAppInstallation = restrictions.blocksAppInstallation ? true : nil
        // Strict Mode's doors. Set through ManagedSettings rather than checked by us, so
        // they hold with the app closed -- which is the only time they matter.
        managedSettingsStore.application.denyAppRemoval = guards.preventsAppRemoval ? true : nil
        managedSettingsStore.dateAndTime.requireAutomaticDateAndTime = guards.preventsDateAndTimeChanges ? true : nil
        managedSettingsStore.passcode.lockPasscode = guards.preventsPasscodeChanges ? true : nil
        try appGroupStore.updateRuntimeState { state in state.shieldPolicy = policy }
    }

    func remove(_ policy: ShieldPolicy) async throws {
        print("Removing shield policy reason=\(String(describing: policy.reason))")
        managedSettingsStore.shield.applications = nil
        managedSettingsStore.shield.webDomains = nil
        managedSettingsStore.shield.applicationCategories = nil
        managedSettingsStore.webContent.blockedByFilter = nil
        managedSettingsStore.appStore.denyInAppPurchases = nil
        managedSettingsStore.appStore.requirePasswordForPurchases = nil
        managedSettingsStore.application.denyAppInstallation = nil
        managedSettingsStore.application.denyAppRemoval = nil
        managedSettingsStore.dateAndTime.requireAutomaticDateAndTime = nil
        managedSettingsStore.passcode.lockPasscode = nil
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
        managedSettingsStore.appStore.denyInAppPurchases = nil
        managedSettingsStore.appStore.requirePasswordForPurchases = nil
        managedSettingsStore.application.denyAppInstallation = nil
        managedSettingsStore.application.denyAppRemoval = nil
        managedSettingsStore.dateAndTime.requireAutomaticDateAndTime = nil
        managedSettingsStore.passcode.lockPasscode = nil
        try appGroupStore.saveRuntimeState(.empty)
        print("Cleared all ManagedSettings restrictions and reset runtime state.")
    }

    /// The web filter for a policy, or nil when it wants nothing filtered.
    ///
    /// `.auto` carries both jobs: its argument is the set of sites to block, and turning
    /// it on at all is what enables the automatic adult-content filter.
    private func webContentFilter(
        blocking domains: Set<ManagedSettings.WebDomain>,
        restrictions: ContentRestrictions
    ) -> ManagedSettings.WebContentSettings.FilterPolicy? {
        guard !domains.isEmpty || restrictions.blocksAdultWebContent else { return nil }
        return .auto(domains)
    }
}
