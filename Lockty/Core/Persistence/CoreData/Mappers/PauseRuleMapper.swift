import CoreData
import FamilyControls
import Foundation
import ManagedSettings

enum PauseRuleMapperError: LocalizedError {
    case invalidPayload
    var errorDescription: String? { "A saved Pause rule could not be decoded." }
}

struct PauseRuleMapper {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func apply(
        _ rule: PauseRule,
        to entity: PauseRuleEntity,
        context: NSManagedObjectContext
    ) throws {
        let selection = makeSelection(from: rule.application.applicationToken)
        entity.id = rule.id
        entity.appID = rule.application.id.rawValue
        entity.appDisplayName = rule.application.displayName
        entity.appBundleIdentifier = rule.application.bundleIdentifier
        entity.appTokenData = ApplicationTokenCoding.encode(rule.application.applicationToken)
        entity.familyActivitySelectionData = try selection?.archivedData()
        entity.appIconSystemName = rule.application.iconSystemName
        entity.appIconArtworkURL = rule.application.iconSource.remoteURL?.absoluteString
        entity.isEnabled = rule.isEnabled
        entity.allowanceDuration = rule.allowanceDuration
        entity.relockAfterAllowance = rule.relockAfterAllowance
        entity.createdAt = rule.createdAt
        entity.updatedAt = rule.updatedAt

        try ChildDiffSync.apply(
            context: context,
            domainItems: Array(rule.steps.enumerated()),
            domainID: { $0.element.id },
            existing: entity.steps,
            entityID: { $0.id },
            makeNew: { context in
                let created = PauseStepEntity(context: context)
                created.pauseRule = entity
                return created
            },
            apply: { stepEntity, indexed in
                stepEntity.id = indexed.element.id
                stepEntity.order = Int16(indexed.offset)
                stepEntity.kindRawValue = Self.kindRawValue(for: indexed.element)
                stepEntity.configData = try self.encoder.encode(indexed.element)
            }
        )
    }

    func makeDomain(from entity: PauseRuleEntity) throws -> PauseRule {
        let source: AppIconSource = entity.appIconArtworkURL.map { .appStoreArtworkURL($0) }
            ?? entity.appIconSystemName.map { .systemImage($0) }
            ?? .placeholder
        let selection = try self.selection(from: entity)
        let application = AppIdentity(
            id: AppIdentity.ID(rawValue: entity.appID),
            displayName: entity.appDisplayName,
            bundleIdentifier: entity.appBundleIdentifier,
            applicationToken: ApplicationTokenCoding.decode(entity.appTokenData) ?? selection?.applicationTokens.first,
            iconSystemName: entity.appIconSystemName,
            iconSource: source
        )

        do {
            let steps = try entity.steps
                .sorted { $0.order < $1.order }
                .map { try decoder.decode(PauseStep.self, from: $0.configData) }

            return PauseRule(
                id: entity.id,
                application: application,
                isEnabled: entity.isEnabled,
                steps: steps,
                allowanceDuration: entity.allowanceDuration,
                relockAfterAllowance: entity.relockAfterAllowance,
                createdAt: entity.createdAt,
                updatedAt: entity.updatedAt
            )
        } catch {
            throw PauseRuleMapperError.invalidPayload
        }
    }

    func selection(from entity: PauseRuleEntity) throws -> FamilyActivitySelection? {
        do {
            return try FamilyActivitySelection.unarchive(from: entity.familyActivitySelectionData)
        } catch {
            throw PauseRuleMapperError.invalidPayload
        }
    }

    private func makeSelection(from token: ApplicationToken?) -> FamilyActivitySelection? {
        guard let token else { return nil }
        var selection = FamilyActivitySelection()
        selection.applicationTokens = [token]
        return selection
    }

    private static func kindRawValue(for step: PauseStep) -> String {
        switch step {
        case .countdown: "countdown"
        case .breathing: "breathing"
        case .intention: "intention"
        case .confirmation: "confirmation"
        }
    }
}
