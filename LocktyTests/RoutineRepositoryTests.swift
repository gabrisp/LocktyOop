import Foundation
import Testing
@testable import Lockty

@MainActor
@Suite("Core Data routine repository")
struct RoutineRepositoryTests {
    private func makeRepository() -> CoreDataRoutineRepository {
        let controller = CoreDataTestSupport.makeInMemoryController()
        let selectionStore = ScreenTimeSelectionStore(appGroupStore: AppGroupStore())
        return CoreDataRoutineRepository(controller: controller, selectionStore: selectionStore)
    }

    @Test
    func savesAndFetchesRoutineWithChildren() async throws {
        let repository = makeRepository()

        let routine = Routine(
            name: "Deep Work",
            icon: "brain.head.profile",
            mode: .strict,
            triggers: [.manual, .schedule(RoutineSchedule(hour: 9, minute: 0, weekdays: [.monday, .wednesday]))],
            blockedApplications: ["instagram", "youtube"],
            blockedDomains: ["instagram.com"],
            tasks: [
                RoutineTask(title: "Read", order: 0),
                RoutineTask(title: "Journal", order: 1, isOptional: true)
            ],
            breakPolicy: BreakPolicy(maximumBreaks: 2, maximumDuration: 600, minimumInterval: 1800, allowedTriggers: [.manual])
        )

        try await repository.save(routine)
        let fetched = try await repository.routines()

        #expect(fetched.count == 1)
        let saved = try #require(fetched.first)
        #expect(saved.id == routine.id)
        #expect(saved.name == "Deep Work")
        #expect(saved.tasks.count == 2)
        #expect(saved.tasks.map(\.title) == ["Read", "Journal"])
        #expect(saved.triggers.count == 2)
        #expect(saved.blockedApplications == ["instagram", "youtube"])
        #expect(saved.blockedDomains == ["instagram.com"])
        #expect(saved.breakPolicy.maximumBreaks == 2)
    }

    @Test
    func updatingRoutineReplacesTasksRatherThanDuplicating() async throws {
        let repository = makeRepository()

        var routine = Routine(
            name: "Morning",
            mode: .normal,
            triggers: [.manual],
            blockedApplications: [],
            blockedDomains: [],
            tasks: [RoutineTask(title: "Coffee", order: 0)],
            breakPolicy: .none
        )
        try await repository.save(routine)

        routine.name = "Morning Reset"
        routine.tasks = [RoutineTask(title: "Coffee", order: 0), RoutineTask(title: "Stretch", order: 1)]
        try await repository.save(routine)

        let fetched = try await repository.routines()
        #expect(fetched.count == 1)
        let saved = try #require(fetched.first)
        #expect(saved.name == "Morning Reset")
        #expect(saved.tasks.count == 2)
    }

    @Test
    func deletesRoutine() async throws {
        let repository = makeRepository()

        let routine = Routine(
            name: "Temp",
            mode: .normal,
            triggers: [.manual],
            blockedApplications: [],
            blockedDomains: [],
            tasks: [],
            breakPolicy: .none
        )
        try await repository.save(routine)
        try await repository.delete(id: routine.id)

        let fetched = try await repository.routines()
        #expect(fetched.isEmpty)
    }
}
