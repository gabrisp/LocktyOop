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
            if let matched = records().first(where: { record in
                guard case .pause = record.scope else { return false }
                return record.blockedApplications.contains(appID)
            }) {
                return matched.selection
            }
            return FamilyActivitySelection()
        case .combined:
            return mergedSelection(for: policy)
        case .none:
            return FamilyActivitySelection()
        }
    }

    func mergedSelection(for policy: ShieldPolicy) -> FamilyActivitySelection {
        let matchingRecords = records().filter { record in
            !record.blockedApplications.isDisjoint(with: policy.blockedApplications)
                || !record.blockedDomains.isDisjoint(with: policy.blockedDomains)
        }

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
