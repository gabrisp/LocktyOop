import Foundation
import SwiftData

@MainActor
final class PersistenceStore {
    let container: ModelContainer?
    private(set) var initializationError: Error?

    init() {
        do {
            container = try ModelContainer(
                for: RoutineRecord.self,
                RoutineExecutionRecord.self,
                PauseRuleRecord.self,
                PauseEventRecord.self,
                AppClassificationRecord.self
            )
        } catch {
            container = nil
            initializationError = error
        }
    }

    var context: ModelContext? {
        container.map(ModelContext.init)
    }
}
