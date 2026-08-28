import Foundation
import FamilyControls
import ManagedSettings
import OSLog

private func selectionLogger() -> Logger {
    Logger(subsystem: "com.gabrisp.Lockty", category: "selection")
}

struct ScreenTimeSelectionStore {
    private let appGroupStore: AppGroupStore

    nonisolated init(appGroupStore: AppGroupStore = AppGroupStore()) {
        self.appGroupStore = appGroupStore
    }

    func load(scope: ScreenTimeSelectionScope) throws -> FamilyActivitySelection {
        let selection = records().first(where: { $0.scope == scope })?.selection ?? FamilyActivitySelection()
        selectionLogger().debug("Loaded selection for scope=\(scope.id, privacy: .public) apps=\(selection.applicationTokens.count) categories=\(selection.categoryTokens.count) domains=\(selection.webDomainTokens.count)")
        print("Loaded selection scope=\(scope.id) apps=\(selection.applicationTokens.count) categories=\(selection.categoryTokens.count) domains=\(selection.webDomainTokens.count)")
        return selection
    }

    func save(_ selection: FamilyActivitySelection, scope: ScreenTimeSelectionScope) throws {
        var storedRecords = records()
        let record = ScreenTimeSelectionRecord(scope: scope, selection: selection)
        if let index = storedRecords.firstIndex(where: { $0.scope == scope }) {
            storedRecords[index] = record
        } else {
            storedRecords.append(record)
        }
        try appGroupStore.saveSelectionRecords(storedRecords)
        selectionLogger().notice("Saved selection for scope=\(scope.id, privacy: .public) apps=\(selection.applicationTokens.count) categories=\(selection.categoryTokens.count) domains=\(selection.webDomainTokens.count)")
        print("Saved selection scope=\(scope.id) apps=\(selection.applicationTokens.count) categories=\(selection.categoryTokens.count) domains=\(selection.webDomainTokens.count)")
    }

    func remove(scope: ScreenTimeSelectionScope) throws {
        var storedRecords = records()
        let previousCount = storedRecords.count
        storedRecords.removeAll { $0.scope == scope }
        guard storedRecords.count != previousCount else {
            print("No selection record found to remove for scope=\(scope.id)")
            return
        }
        try appGroupStore.saveSelectionRecords(storedRecords)
        selectionLogger().notice("Removed selection for scope=\(scope.id, privacy: .public)")
        print("Removed selection scope=\(scope.id)")
    }

    func record(scope: ScreenTimeSelectionScope) -> ScreenTimeSelectionRecord? {
        records().first(where: { $0.scope == scope })
    }

    func pauseRuleID(matching applicationToken: ApplicationToken) -> UUID? {
        records().first { record in
            guard case .pause = record.scope else { return false }
            return record.selection.applicationTokens.contains(applicationToken)
        }.flatMap { record in
            guard case .pause(let ruleID) = record.scope else { return nil }
            return ruleID
        }
    }

    func selection(for policy: ShieldPolicy) throws -> FamilyActivitySelection {
        switch policy.reason {
        case .routine(let routineID):
            return try load(scope: .routine(routineID))
        case .pause(let appID):
            if let matched = records()
                .filter({ record in
                guard case .pause = record.scope else { return false }
                return record.blockedApplications.contains(appID)
                })
                .sorted(by: { $0.updatedAt > $1.updatedAt })
                .first {
                print("Resolved pause selection for appID=\(appID.rawValue) from scope=\(matched.scope.id)")
                return matched.selection
            }
            print("No pause selection found for appID=\(appID.rawValue)")
            return FamilyActivitySelection()
        case .combined:
            return mergedSelection(for: policy)
        case .none:
            return FamilyActivitySelection()
        }
    }

    func mergedSelection(for policy: ShieldPolicy) -> FamilyActivitySelection {
        let matchingRecords = records().filter { record in
            record.isContained(in: policy)
        }

        print(
            """
            Merging selection for policy reason=\(String(describing: policy.reason)) \
            policyApps=\(policy.blockedApplications.count) \
            policyDomains=\(policy.blockedDomains.count) \
            matchedScopes=\(matchingRecords.map(\.scope.id))
            """
        )

        return matchingRecords.reduce(into: FamilyActivitySelection()) { partialResult, record in
            partialResult.applicationTokens.formUnion(record.selection.applicationTokens)
            partialResult.categoryTokens.formUnion(record.selection.categoryTokens)
            partialResult.webDomainTokens.formUnion(record.selection.webDomainTokens)
        }
    }

    func records() -> [ScreenTimeSelectionRecord] {
        let loadedRecords = appGroupStore.loadSelectionRecords()
        selectionLogger().debug("Loaded selection record count=\(loadedRecords.count)")
        print("Loaded selection record count=\(loadedRecords.count)")
        return loadedRecords
    }
}
