import Foundation
import FamilyControls
import ManagedSettings
import OSLog

private nonisolated func selectionLogger() -> Logger {
    Logger(subsystem: "com.gabrisp.Lockty", category: "selection")
}

/// Reading a selection is plain file work -- decode a record, hand it back.
///
/// The read paths are `nonisolated` because the callers that matter are not on the main
/// actor and never could be: the shield action extension asking which rule holds an app,
/// the monitor extension recomputing a policy, the store resolving Always Allowed. Only
/// the writes stay isolated, since nothing off the main actor writes.
struct ScreenTimeSelectionStore {
    private let appGroupStore: AppGroupStore

    nonisolated init(appGroupStore: AppGroupStore = AppGroupStore()) {
        self.appGroupStore = appGroupStore
    }

    nonisolated func load(scope: ScreenTimeSelectionScope) throws -> FamilyActivitySelection {
        let selection = records().first(where: { $0.scope == scope })?.selection ?? FamilyActivitySelection()
        selectionLogger().debug("Loaded selection for scope=\(scope.id, privacy: .public) apps=\(selection.applicationTokens.count) categories=\(selection.categoryTokens.count) domains=\(selection.webDomainTokens.count)")
        return selection
    }

    func save(_ selection: FamilyActivitySelection, scope: ScreenTimeSelectionScope) throws {
        var storedRecords = records()

        // Nothing to do when it is already what is stored.
        //
        // One guard, in the one place every write goes through. Loading the routines wrote
        // all four of their selections back every time -- and each write re-reads and
        // re-encodes a file of two hundred records -- so opening Focus was a dozen reads
        // and a dozen writes to save exactly what was already there.
        if let existing = storedRecords.first(where: { $0.scope == scope }),
           existing.selection.applicationTokens == selection.applicationTokens,
           existing.selection.categoryTokens == selection.categoryTokens,
           existing.selection.webDomainTokens == selection.webDomainTokens {
            return
        }

        let record = ScreenTimeSelectionRecord(scope: scope, selection: selection)
        if let index = storedRecords.firstIndex(where: { $0.scope == scope }) {
            storedRecords[index] = record
        } else {
            storedRecords.append(record)
        }
        try appGroupStore.saveSelectionRecords(storedRecords)
        SelectionRecordCache.shared.invalidate()
        selectionLogger().notice("Saved selection for scope=\(scope.id, privacy: .public) apps=\(selection.applicationTokens.count) categories=\(selection.categoryTokens.count) domains=\(selection.webDomainTokens.count)")
    }

    func remove(scope: ScreenTimeSelectionScope) throws {
        var storedRecords = records()
        let previousCount = storedRecords.count
        storedRecords.removeAll { $0.scope == scope }
        guard storedRecords.count != previousCount else {
            return
        }
        try appGroupStore.saveSelectionRecords(storedRecords)
        SelectionRecordCache.shared.invalidate()
        selectionLogger().notice("Removed selection for scope=\(scope.id, privacy: .public)")
    }

    nonisolated func record(scope: ScreenTimeSelectionScope) -> ScreenTimeSelectionRecord? {
        records().first(where: { $0.scope == scope })
    }

    nonisolated func pauseRuleID(matching applicationToken: ApplicationToken) -> UUID? {
        records().first { record in
            guard case .pause = record.scope else { return false }
            return record.selection.applicationTokens.contains(applicationToken)
        }.flatMap { record in
            guard case .pause(let ruleID) = record.scope else { return nil }
            return ruleID
        }
    }

    /// The tokens, across every stored selection, for the given app identities.
    ///
    /// An AppIdentity.ID is derived from its token, so this walks the records rather
    /// than trying to reconstruct a token from the identity -- which is not possible.
    nonisolated func applicationTokens(for appIDs: Set<AppIdentity.ID>) -> Set<ApplicationToken> {
        guard !appIDs.isEmpty else { return [] }
        var tokens = Set<ApplicationToken>()
        for record in records() {
            for token in record.selection.applicationTokens where appIDs.contains(AppIdentity.ID(token: token)) {
                tokens.insert(token)
            }
        }
        return tokens
    }

    nonisolated func selection(for policy: ShieldPolicy) throws -> FamilyActivitySelection {
        if !policy.selectionScopes.isEmpty {
            return mergedSelection(scopes: policy.selectionScopes)
        }

        switch policy.reason {
        case .routine(let routineID):
            return try load(scope: .routine(routineID))
        case .rule(let ruleID):
            return try load(scope: .rule(ruleID))
        case .pause(let appID):
            if let matched = records()
                .filter({ record in
                guard case .pause = record.scope else { return false }
                return record.blockedApplications.contains(appID)
                })
                .sorted(by: { $0.updatedAt > $1.updatedAt })
                .first {
                return matched.selection
            }
            return FamilyActivitySelection()
        case .combined:
            return mergedSelection(for: policy)
        case .none:
            return FamilyActivitySelection()
        }
    }

    nonisolated func mergedSelection(for policy: ShieldPolicy) -> FamilyActivitySelection {
        let matchingRecords = records().filter { record in
            record.isContained(in: policy)
        }

        return matchingRecords.reduce(into: FamilyActivitySelection()) { partialResult, record in
            partialResult.applicationTokens.formUnion(record.selection.applicationTokens)
            partialResult.categoryTokens.formUnion(record.selection.categoryTokens)
            partialResult.webDomainTokens.formUnion(record.selection.webDomainTokens)
        }
    }

    nonisolated func mergedSelection(scopes: Set<ScreenTimeSelectionScope>) -> FamilyActivitySelection {
        let matchingRecords = records().filter { scopes.contains($0.scope) }
        return matchingRecords.reduce(into: FamilyActivitySelection()) { partialResult, record in
            partialResult.applicationTokens.formUnion(record.selection.applicationTokens)
            partialResult.categoryTokens.formUnion(record.selection.categoryTokens)
            partialResult.webDomainTokens.formUnion(record.selection.webDomainTokens)
        }
    }

    /// Every stored selection, from memory when it was read a moment ago.
    ///
    /// This is the hottest read in the app and the most expensive one: the file holds a
    /// couple of hundred records and each carries a `FamilyActivitySelection`, whose tokens
    /// are opaque blobs that are slow to decode. It is called from `load`, from `record`,
    /// from `mergedSelection` -- which itself runs once per rule, per limit and per shield
    /// policy -- so a single pass over Today or Focus decoded that file dozens of times
    /// over for an answer that had not changed. The log was full of nothing else.
    ///
    /// Cached for a second, and dropped the moment this process writes. A second is long
    /// enough to collapse a screen's worth of reads into one and short enough that nothing
    /// another process wrote can be missed by more than that.
    nonisolated func records() -> [ScreenTimeSelectionRecord] {
        if let cached = SelectionRecordCache.shared.records() {
            return cached
        }

        let loadedRecords = appGroupStore.loadSelectionRecords()
        SelectionRecordCache.shared.store(loadedRecords)
        selectionLogger().debug("Loaded selection record count=\(loadedRecords.count)")
        return loadedRecords
    }
}

/// The records, briefly remembered.
///
/// A class with a lock rather than an actor: every reader here is `nonisolated` and most
/// are not on the main actor -- the extensions read this too -- and making them await
/// would mean making half the app's read paths async for a cache.
private final class SelectionRecordCache: @unchecked Sendable {
    static let shared = SelectionRecordCache()

    /// How long a read stays good for. Long enough to cover one screen's worth of calls.
    private let lifetime: TimeInterval = 1

    private let lock = NSLock()
    private var cached: [ScreenTimeSelectionRecord]?
    private var readAt: Date?

    func records() -> [ScreenTimeSelectionRecord]? {
        lock.lock()
        defer { lock.unlock() }

        guard let cached, let readAt, Date().timeIntervalSince(readAt) < lifetime else { return nil }
        return cached
    }

    func store(_ records: [ScreenTimeSelectionRecord]) {
        lock.lock()
        defer { lock.unlock() }
        cached = records
        readAt = Date()
    }

    /// After a write of our own, so the next read is the truth rather than the second
    /// before it.
    func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        cached = nil
        readAt = nil
    }
}
