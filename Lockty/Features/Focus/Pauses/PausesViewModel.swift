import Foundation
import Observation

struct PauseRuleSummaryState: Identifiable, Equatable {
    let id: UUID
    let name: String
    let flow: String
    let successRate: String
    let stopped: Int
    let continued: Int
}

struct PausesOverviewState: Equatable {
    var summary = PauseSuccessSummary(triggeredCount: 0, stoppedCount: 0, continuedCount: 0)
    var reclaimedTimeText = "--"
    var rules: [PauseRuleSummaryState] = []
}

@MainActor
@Observable
final class PausesViewModel {
    private let ruleRepository: PauseRuleRepository
    private let eventRepository: PauseEventRepository
    private let calculator: PauseSuccessCalculating
    private(set) var state = PausesOverviewState()

    init(
        ruleRepository: PauseRuleRepository,
        eventRepository: PauseEventRepository,
        calculator: PauseSuccessCalculating
    ) {
        self.ruleRepository = ruleRepository
        self.eventRepository = eventRepository
        self.calculator = calculator
    }

    func load() async {
        let rules = await ruleRepository.rules()
        let events = await eventRepository.events(from: nil, to: nil)
        state = PausesOverviewState(
            summary: calculator.summary(from: events),
            reclaimedTimeText: LocktyDurationFormatter.abbreviated(TimeInterval(events.filter { $0.decision == .abandoned }.count) * 4 * 60),
            rules: rules.map { rule in
                let ruleEvents = events.filter { $0.pauseRuleID == rule.id }
                let summary = calculator.summary(from: ruleEvents)
                return PauseRuleSummaryState(
                    id: rule.id,
                    name: rule.application.displayName,
                    flow: rule.steps.map(\.title).joined(separator: " -> "),
                    successRate: summary.successRateValue.map { "\($0)% success" } ?? "No decisions",
                    stopped: summary.stoppedCount,
                    continued: summary.continuedCount
                )
            }
        )
    }
}
