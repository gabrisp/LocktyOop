import CoreData
import FamilyControls
import Foundation

enum RoutineMapperError: LocalizedError {
    case invalidMode
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .invalidMode:
            "The persisted routine mode is invalid."
        case .invalidPayload:
            "The persisted routine payload could not be decoded."
        }
    }
}

struct RoutineMapper {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func apply(
        _ routine: Routine,
        selection: FamilyActivitySelection?,
        to entity: RoutineEntity,
        context: NSManagedObjectContext
    ) throws {
        entity.id = routine.id
        entity.name = routine.name
        entity.icon = routine.icon
        entity.colorHex = routine.colorHex
        entity.modeRawValue = routine.mode.rawValue
        entity.allowsPauseDuringStrictMode = routine.allowsPauseDuringStrictMode
        entity.createdAt = routine.createdAt
        entity.updatedAt = routine.updatedAt
        entity.blockedApplicationIDsData = try encoder.encode(routine.blockedApplications)
        entity.blockedDomainsData = try encoder.encode(routine.blockedDomains)
        entity.breakPolicyData = try encoder.encode(routine.breakPolicy)
        entity.familyActivitySelectionData = try selection?.archivedData()

        ChildDiffSync.apply(
            context: context,
            domainItems: routine.tasks,
            domainID: { $0.id },
            existing: entity.tasks,
            entityID: { $0.id },
            makeNew: { context in
                let created = RoutineTaskEntity(context: context)
                created.routine = entity
                return created
            },
            apply: { taskEntity, task in
                taskEntity.id = task.id
                taskEntity.title = task.title
                taskEntity.icon = task.icon
                taskEntity.order = Int16(task.order)
                taskEntity.isOptional = task.isOptional
            }
        )

        try ChildDiffSync.apply(
            context: context,
            domainItems: routine.triggers,
            domainID: { Self.stableTriggerID(for: $0) },
            existing: entity.triggers,
            entityID: { $0.id },
            makeNew: { context in
                let created = RoutineTriggerEntity(context: context)
                created.routine = entity
                return created
            },
            apply: { triggerEntity, trigger in
                triggerEntity.id = Self.stableTriggerID(for: trigger)
                triggerEntity.kindRawValue = Self.kindRawValue(for: trigger)
                if case .manual = trigger {
                    triggerEntity.configData = nil
                } else {
                    triggerEntity.configData = try self.encoder.encode(trigger)
                }
            }
        )
    }

    func makeDomain(from entity: RoutineEntity) throws -> Routine {
        guard let mode = RoutineMode(rawValue: entity.modeRawValue) else {
            throw RoutineMapperError.invalidMode
        }

        do {
            let tasks = entity.tasks
                .map { taskEntity in
                    RoutineTask(
                        id: taskEntity.id,
                        title: taskEntity.title,
                        icon: taskEntity.icon,
                        order: Int(taskEntity.order),
                        isOptional: taskEntity.isOptional
                    )
                }
                .sorted { $0.order < $1.order }

            let triggers: [RoutineTrigger] = try entity.triggers.map { triggerEntity in
                if let data = triggerEntity.configData {
                    return try decoder.decode(RoutineTrigger.self, from: data)
                }
                return .manual
            }

            return Routine(
                id: entity.id,
                name: entity.name,
                icon: entity.icon,
                colorHex: entity.colorHex,
                mode: mode,
                triggers: triggers.isEmpty ? [.manual] : triggers,
                blockedApplications: try decoder.decode(Set<AppIdentity.ID>.self, from: entity.blockedApplicationIDsData),
                blockedDomains: try decoder.decode(Set<String>.self, from: entity.blockedDomainsData),
                tasks: tasks,
                breakPolicy: try decoder.decode(BreakPolicy.self, from: entity.breakPolicyData),
                allowsPauseDuringStrictMode: entity.allowsPauseDuringStrictMode,
                createdAt: entity.createdAt,
                updatedAt: entity.updatedAt
            )
        } catch {
            throw RoutineMapperError.invalidPayload
        }
    }

    func selection(from entity: RoutineEntity) throws -> FamilyActivitySelection? {
        do { return try FamilyActivitySelection.unarchive(from: entity.familyActivitySelectionData) }
        catch { throw RoutineMapperError.invalidPayload }
    }

    private static func kindRawValue(for trigger: RoutineTrigger) -> String {
        switch trigger {
        case .manual: "manual"
        case .schedule: "schedule"
        case .alarm: "alarm"
        case .nfc: "nfc"
        case .location: "location"
        }
    }

    /// `RoutineTrigger.id` is a String derived from an inner UUID; this recovers a stable
    /// UUID to key the Core Data child row on when the string isn't itself a UUID (e.g. "manual").
    private static func stableTriggerID(for trigger: RoutineTrigger) -> UUID {
        switch trigger {
        case .manual:
            UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        case .schedule(let schedule):
            schedule.id
        case .alarm(let alarm):
            alarm.id
        case .nfc(let action):
            action.id
        case .location(let location):
            location.id
        }
    }
}
