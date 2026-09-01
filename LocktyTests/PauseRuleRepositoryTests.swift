import Foundation
import Testing
@testable import Lockty

@MainActor
@Suite("Core Data pause rule repository")
struct PauseRuleRepositoryTests {
    private func makeRepository() -> CoreDataPauseRuleRepository {
        let controller = CoreDataTestSupport.makeInMemoryController()
        let appGroupStore = AppGroupStore()
        let selectionStore = ScreenTimeSelectionStore(appGroupStore: appGroupStore)
        return CoreDataPauseRuleRepository(controller: controller, appGroupStore: appGroupStore, selectionStore: selectionStore)
    }

    @Test
    func savesAndFetchesRuleWithOrderedSteps() async throws {
        let repository = makeRepository()

        let rule = PauseRule(
            application: AppIdentity(id: "instagram", displayName: "Instagram"),
            isEnabled: true,
            steps: [
                .countdown(CountdownConfiguration(duration: 10)),
                .intention(IntentionConfiguration(prompt: "Why?", minimumLength: 10, isRequired: true)),
                .confirmation(ConfirmationConfiguration())
            ],
            allowanceDuration: 300
        )

        try await repository.save(rule)
        let fetched = await repository.rules()

        #expect(fetched.count == 1)
        let saved = fetched.first
        #expect(saved?.id == rule.id)
        #expect(saved?.steps.count == 3)
        if case .countdown = saved?.steps.first {
            // ordering preserved
        } else {
            Issue.record("Expected countdown step first, order was not preserved")
        }
        if case .confirmation = saved?.steps.last {
            // ordering preserved
        } else {
            Issue.record("Expected confirmation step last, order was not preserved")
        }
    }

    @Test
    func fetchesRuleByAppID() async throws {
        let repository = makeRepository()
        let rule = PauseRule(
            application: AppIdentity(id: "tiktok", displayName: "TikTok"),
            isEnabled: true,
            steps: [.countdown(CountdownConfiguration(duration: 5))],
            allowanceDuration: 120
        )
        try await repository.save(rule)

        let fetched = await repository.rule(for: "tiktok")
        #expect(fetched?.id == rule.id)
    }

    @Test
    func deletesRule() async throws {
        let repository = makeRepository()
        let rule = PauseRule(
            application: AppIdentity(id: "x", displayName: "X"),
            isEnabled: true,
            steps: [.countdown(CountdownConfiguration(duration: 5))],
            allowanceDuration: 60
        )
        try await repository.save(rule)
        try await repository.delete(id: rule.id)

        let fetched = await repository.rules()
        #expect(fetched.isEmpty)
    }
}
