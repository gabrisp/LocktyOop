import Foundation
import FamilyControls

enum RoutineRecordMapperError: LocalizedError {
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

struct RoutineRecordMapper {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func makeRecord(from routine: Routine, selection: FamilyActivitySelection?) throws -> RoutineRecord {
        RoutineRecord(
            id: routine.id,
            name: routine.name,
            icon: routine.icon,
            mode: routine.mode,
            triggersData: try encoder.encode(routine.triggers),
            familyActivitySelectionData: try selection?.archivedData(),
            blockedApplicationIDsData: try encoder.encode(routine.blockedApplications),
            blockedDomainsData: try encoder.encode(routine.blockedDomains),
            tasksData: try encoder.encode(routine.tasks),
            breakPolicyData: try encoder.encode(routine.breakPolicy),
            allowsPauseDuringStrictMode: routine.allowsPauseDuringStrictMode,
            createdAt: routine.createdAt,
            updatedAt: routine.updatedAt
        )
    }

    func makeDomain(from record: RoutineRecord) throws -> Routine {
        guard let mode = RoutineMode(rawValue: record.modeRawValue) else {
            throw RoutineRecordMapperError.invalidMode
        }

        do {
            return Routine(
                id: record.id,
                name: record.name,
                icon: record.icon,
                mode: mode,
                triggers: try decoder.decode([RoutineTrigger].self, from: record.triggersData),
                blockedApplications: try decoder.decode(Set<AppIdentity.ID>.self, from: record.blockedApplicationIDsData),
                blockedDomains: try decoder.decode(Set<String>.self, from: record.blockedDomainsData),
                tasks: try decoder.decode([RoutineTask].self, from: record.tasksData),
                breakPolicy: try decoder.decode(BreakPolicy.self, from: record.breakPolicyData),
                allowsPauseDuringStrictMode: record.allowsPauseDuringStrictMode,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt
            )
        } catch {
            throw RoutineRecordMapperError.invalidPayload
        }
    }

    func selection(from record: RoutineRecord) throws -> FamilyActivitySelection? {
        do { return try FamilyActivitySelection.unarchive(from: record.familyActivitySelectionData) }
        catch { throw RoutineRecordMapperError.invalidPayload }
    }
}
