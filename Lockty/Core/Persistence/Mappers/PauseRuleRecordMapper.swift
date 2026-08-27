import Foundation
import ManagedSettings

enum PauseRuleRecordMapperError: LocalizedError {
    case invalidPayload
    var errorDescription: String? { "A saved Pause rule could not be decoded." }
}

struct PauseRuleRecordMapper {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func makeRecord(from rule: PauseRule) throws -> PauseRuleRecord {
        return PauseRuleRecord(
            id: rule.id,
            application: rule.application,
            isEnabled: rule.isEnabled,
            stepsData: try encoder.encode(rule.steps),
            allowanceDuration: rule.allowanceDuration,
            relockAfterAllowance: rule.relockAfterAllowance,
            createdAt: rule.createdAt,
            updatedAt: rule.updatedAt
        )
    }

    func makeDomain(from record: PauseRuleRecord) throws -> PauseRule {
        let source: AppIconSource = record.appIconArtworkURL.map { .appStoreArtworkURL($0) } ?? record.appIconSystemName.map { .systemImage($0) } ?? .placeholder
        let applicationToken = record.appTokenData.flatMap { try? decoder.decode(ManagedSettings.ApplicationToken?.self, from: $0) }
        let application = AppIdentity(
            id: AppIdentity.ID(rawValue: record.appID),
            displayName: record.appDisplayName,
            bundleIdentifier: record.appBundleIdentifier,
            applicationToken: applicationToken,
            iconSystemName: record.appIconSystemName,
            iconSource: source
        )
        do {
            return PauseRule(id: record.id, application: application, isEnabled: record.isEnabled, steps: try decoder.decode([PauseStep].self, from: record.stepsData), allowanceDuration: record.allowanceDuration, relockAfterAllowance: record.relockAfterAllowance, createdAt: record.createdAt, updatedAt: record.updatedAt)
        } catch { throw PauseRuleRecordMapperError.invalidPayload }
    }
}
