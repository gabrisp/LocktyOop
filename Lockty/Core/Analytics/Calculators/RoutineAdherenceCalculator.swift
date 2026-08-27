import Foundation

nonisolated struct RoutineAdherenceInput: Equatable {
    var completedExecutions: Int
    var attemptedExecutions: Int
    var completedTasks: Int
    var totalTasks: Int
}

nonisolated struct RoutineAdherenceResult: Equatable {
    var executionCompletionRate: Double
    var taskCompletionRate: Double
    var combinedRate: Double
}

protocol RoutineAdherenceCalculating {
    func calculate(from input: RoutineAdherenceInput) -> RoutineAdherenceResult
}

struct RoutineAdherenceCalculator: RoutineAdherenceCalculating {
    func calculate(from input: RoutineAdherenceInput) -> RoutineAdherenceResult {
        let executionRate: Double
        if input.attemptedExecutions > 0 {
            executionRate = Double(max(input.completedExecutions, 0)) / Double(input.attemptedExecutions)
        } else {
            executionRate = 0
        }

        let taskRate: Double
        if input.totalTasks > 0 {
            taskRate = Double(max(input.completedTasks, 0)) / Double(input.totalTasks)
        } else {
            taskRate = 0
        }

        return RoutineAdherenceResult(
            executionCompletionRate: min(max(executionRate, 0), 1),
            taskCompletionRate: min(max(taskRate, 0), 1),
            combinedRate: min(max((executionRate * 0.65) + (taskRate * 0.35), 0), 1)
        )
    }
}
