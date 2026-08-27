import CoreData
import Foundation

struct RoutineExecutionMapper {
    func apply(
        _ execution: RoutineExecution,
        to entity: RoutineExecutionEntity,
        context: NSManagedObjectContext
    ) {
        entity.id = execution.id
        entity.routineID = execution.routineID
        entity.routineName = execution.routineName
        entity.startedAt = execution.startedAt
        entity.endedAt = execution.endedAt
        entity.completionReasonRawValue = execution.completionReason?.rawValue

        ChildDiffSync.apply(
            context: context,
            domainItems: execution.taskCompletions,
            domainID: { $0.id },
            existing: entity.taskCompletions,
            entityID: { $0.id },
            makeNew: { context in
                let created = RoutineTaskCompletionEntity(context: context)
                created.execution = entity
                return created
            },
            apply: { completionEntity, completion in
                completionEntity.id = completion.id
                completionEntity.taskID = completion.taskID
                completionEntity.titleSnapshot = completion.titleSnapshot
                completionEntity.orderSnapshot = Int16(completion.orderSnapshot)
                completionEntity.completedAt = completion.completedAt
            }
        )

        ChildDiffSync.apply(
            context: context,
            domainItems: execution.breakHistory,
            domainID: { $0.id },
            existing: entity.breakEvents,
            entityID: { $0.id },
            makeNew: { context in
                let created = RoutineBreakEventEntity(context: context)
                created.execution = entity
                return created
            },
            apply: { breakEntity, record in
                breakEntity.id = record.id
                breakEntity.startedAt = record.startedAt
                breakEntity.endedAt = record.endedAt
                breakEntity.triggerRawValue = record.trigger.rawValue
            }
        )
    }

    func makeDomain(from entity: RoutineExecutionEntity) -> RoutineExecution {
        let taskCompletions = entity.taskCompletions
            .map { completionEntity in
                RoutineTaskCompletion(
                    id: completionEntity.id,
                    taskID: completionEntity.taskID,
                    titleSnapshot: completionEntity.titleSnapshot,
                    orderSnapshot: Int(completionEntity.orderSnapshot),
                    completedAt: completionEntity.completedAt
                )
            }
            .sorted { $0.orderSnapshot < $1.orderSnapshot }

        let breakHistory = entity.breakEvents
            .map { breakEntity in
                RoutineBreakRecord(
                    id: breakEntity.id,
                    startedAt: breakEntity.startedAt,
                    endedAt: breakEntity.endedAt,
                    trigger: BreakTrigger(rawValue: breakEntity.triggerRawValue) ?? .manual
                )
            }
            .sorted { $0.startedAt < $1.startedAt }

        return RoutineExecution(
            id: entity.id,
            routineID: entity.routineID,
            routineName: entity.routineName,
            startedAt: entity.startedAt,
            endedAt: entity.endedAt,
            completionReason: entity.completionReasonRawValue.flatMap(RoutineCompletionReason.init(rawValue:)),
            taskCompletions: taskCompletions,
            breakHistory: breakHistory
        )
    }
}
