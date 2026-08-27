import Foundation
import SwiftData
import FamilyControls
import OSLog

private let pauseRepositoryLogger = Logger(subsystem: "com.gabrisp.Lockty", category: "pauses")

@MainActor
final class SwiftDataPauseRuleRepository: PauseRuleRepository {
    private let store: PersistenceStore
    private let appGroupStore: AppGroupStore
    private let selectionStore: ScreenTimeSelectionStore
    private let mapper = PauseRuleRecordMapper()

    init(
        store: PersistenceStore,
        appGroupStore: AppGroupStore = AppGroupStore(),
        selectionStore: ScreenTimeSelectionStore = ScreenTimeSelectionStore()
    ) {
        self.store = store
        self.appGroupStore = appGroupStore
        self.selectionStore = selectionStore
    }

    func rules() async -> [PauseRule] {
        guard let context = store.context, let records = try? context.fetch(FetchDescriptor<PauseRuleRecord>()) else { return [] }
        return records.compactMap { record in
            guard let domain = try? mapper.makeDomain(from: record) else { return nil }
            syncSelectionStore(for: domain)
            return domain
        }.sorted { $0.application.displayName < $1.application.displayName }
    }

    func rule(id: UUID) async -> PauseRule? {
        guard let context = store.context else { return nil }
        let descriptor = FetchDescriptor<PauseRuleRecord>(predicate: #Predicate { $0.id == id })
        guard let rule = try? context.fetch(descriptor).first.flatMap({ try? mapper.makeDomain(from: $0) }) else {
            return nil
        }
        syncSelectionStore(for: rule)
        return rule
    }

    func rule(for appID: AppIdentity.ID) async -> PauseRule? {
        guard let context = store.context else { return nil }
        let descriptor = FetchDescriptor<PauseRuleRecord>(predicate: #Predicate { $0.appID == appID.rawValue })
        guard let rule = try? context.fetch(descriptor).first.flatMap({ try? mapper.makeDomain(from: $0) }) else {
            return nil
        }
        syncSelectionStore(for: rule)
        return rule
    }

    func save(_ rule: PauseRule) async {
        guard let context = store.context, let mapped = try? mapper.makeRecord(from: rule) else { return }
        let descriptor = FetchDescriptor<PauseRuleRecord>(predicate: #Predicate { $0.id == rule.id })
        if let existing = (try? context.fetch(descriptor))?.first {
            existing.appID = mapped.appID
            existing.appDisplayName = mapped.appDisplayName
            existing.appBundleIdentifier = mapped.appBundleIdentifier
            existing.appTokenData = mapped.appTokenData
            existing.appIconSystemName = mapped.appIconSystemName
            existing.appIconArtworkURL = mapped.appIconArtworkURL
            existing.isEnabled = mapped.isEnabled
            existing.stepsData = mapped.stepsData
            existing.allowanceDuration = mapped.allowanceDuration
            existing.relockAfterAllowance = mapped.relockAfterAllowance
            existing.updatedAt = mapped.updatedAt
        } else { context.insert(mapped) }
        try? context.save()
        pauseRepositoryLogger.notice("Saved pause rule id=\(rule.id.uuidString, privacy: .public) app=\(rule.application.displayName, privacy: .public) steps=\(rule.steps.count)")
        syncSelectionStore(for: rule)
        syncSharedSnapshots()
    }

    func delete(id: UUID) async {
        guard let context = store.context else { return }
        let descriptor = FetchDescriptor<PauseRuleRecord>(predicate: #Predicate { $0.id == id })
        if let record = try? context.fetch(descriptor).first {
            context.delete(record)
            try? context.save()
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
        guard let context = store.context, let records = try? context.fetch(FetchDescriptor<PauseRuleRecord>()) else {
            return []
        }
        return records.compactMap { record in
            guard let domain = try? mapper.makeDomain(from: record) else { return nil }
            return PauseRuleSnapshot(rule: domain)
        }
        .sorted { $0.application.displayName.localizedCaseInsensitiveCompare($1.application.displayName) == .orderedAscending }
    }

    private func syncSelectionStore(for rule: PauseRule) {
        guard let token = rule.application.applicationToken else { return }
        var selection = FamilyActivitySelection()
        selection.applicationTokens = [token]
        try? selectionStore.save(selection, scope: .pause(rule.id))
    }
}

@MainActor
final class SwiftDataPauseEventRepository: PauseEventRepository {
    private let store: PersistenceStore
    init(store: PersistenceStore) { self.store = store }

    func events(from startDate: Date?, to endDate: Date?) async -> [PauseEvent] {
        guard let context = store.context, let records = try? context.fetch(FetchDescriptor<PauseEventRecord>()) else { return [] }
        return records.compactMap { record in
            guard (startDate == nil || record.triggeredAt >= startDate!), (endDate == nil || record.triggeredAt < endDate!), let decision = PauseDecision(rawValue: record.decisionRawValue) else { return nil }
            let app = AppIdentity(id: AppIdentity.ID(rawValue: record.appID), displayName: record.appDisplayName)
            return PauseEvent(id: record.id, pauseRuleID: record.pauseRuleID, application: app, triggeredAt: record.triggeredAt, completedAt: record.completedAt, intention: record.intention, decision: decision, allowanceDuration: record.allowanceDuration, actualUsageDuration: record.actualUsageDuration)
        }
    }

    func save(_ event: PauseEvent) async {
        guard let context = store.context else { return }
        context.insert(PauseEventRecord(id: event.id, pauseRuleID: event.pauseRuleID, application: event.application, triggeredAt: event.triggeredAt, completedAt: event.completedAt, intention: event.intention, decision: event.decision, allowanceDuration: event.allowanceDuration, actualUsageDuration: event.actualUsageDuration))
        try? context.save()
        pauseRepositoryLogger.notice("Saved pause event id=\(event.id.uuidString, privacy: .public) app=\(event.application.displayName, privacy: .public) decision=\(event.decision.rawValue, privacy: .public)")
    }
}
