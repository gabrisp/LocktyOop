import Foundation
import SwiftData

protocol AppClassificationRepository {
    func classification(for appID: AppIdentity.ID) async -> AppClassification?
    func allClassifications() async -> [AppIdentity.ID: AppClassification]
    func saveClassification(_ classification: AppClassification, for appID: AppIdentity.ID) async
}

final class InMemoryAppClassificationRepository: AppClassificationRepository {
    private var classifications: [AppIdentity.ID: AppClassification]

    init(classifications: [AppIdentity.ID: AppClassification] = [:]) {
        self.classifications = classifications
    }

    func classification(for appID: AppIdentity.ID) async -> AppClassification? {
        classifications[appID]
    }

    func allClassifications() async -> [AppIdentity.ID: AppClassification] {
        classifications
    }

    func saveClassification(_ classification: AppClassification, for appID: AppIdentity.ID) async {
        classifications[appID] = classification
    }
}

@MainActor
final class SwiftDataAppClassificationRepository: AppClassificationRepository {
    private let store: PersistenceStore

    init(store: PersistenceStore) {
        self.store = store
    }

    func classification(for appID: AppIdentity.ID) async -> AppClassification? {
        guard
            let context = store.context,
            let record = try? context.fetch(
                FetchDescriptor<AppClassificationRecord>(
                    predicate: #Predicate { $0.appID == appID.rawValue }
                )
            ).first
        else {
            return nil
        }

        return AppClassification(rawValue: record.classificationRawValue)
    }

    func allClassifications() async -> [AppIdentity.ID: AppClassification] {
        guard let context = store.context, let records = try? context.fetch(FetchDescriptor<AppClassificationRecord>()) else {
            return [:]
        }

        return records.reduce(into: [:]) { partialResult, record in
            guard let classification = AppClassification(rawValue: record.classificationRawValue) else { return }
            partialResult[AppIdentity.ID(rawValue: record.appID)] = classification
        }
    }

    func saveClassification(_ classification: AppClassification, for appID: AppIdentity.ID) async {
        guard let context = store.context else { return }
        let descriptor = FetchDescriptor<AppClassificationRecord>(
            predicate: #Predicate { $0.appID == appID.rawValue }
        )

        if let existing = try? context.fetch(descriptor).first {
            existing.classificationRawValue = classification.rawValue
            existing.updatedAt = Date()
        } else {
            context.insert(
                AppClassificationRecord(
                    appID: appID.rawValue,
                    displayName: appID.rawValue,
                    classification: classification
                )
            )
        }

        try? context.save()
    }
}
