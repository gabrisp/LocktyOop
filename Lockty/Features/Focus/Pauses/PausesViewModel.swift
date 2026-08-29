import Foundation
import Observation
import SwiftUI

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
    private let routineEngine: RoutineEngine
    private(set) var state = PausesOverviewState()
    private(set) var recentEvents: [PauseEvent] = []

    init(
        ruleRepository: PauseRuleRepository,
        eventRepository: PauseEventRepository,
        calculator: PauseSuccessCalculating,
        routineEngine: RoutineEngine
    ) {
        self.ruleRepository = ruleRepository
        self.eventRepository = eventRepository
        self.calculator = calculator
        self.routineEngine = routineEngine
    }

    /// A running routine freezes the Pauses it enforces, so none can be created or
    /// changed until it ends.
    var isLockedByActiveRoutine: Bool {
        routineEngine.activeRoutine() != nil
    }

    var activeRoutineLockMessage: String {
        let name = routineEngine.activeRoutine()?.nameSnapshot ?? "A routine"
        return "\(name) is running. Pauses can't be changed until it ends."
    }

    /// Pause events recorded since the given moment — used by the live session sheet
    /// to show what happened during the routine that's currently running.
    func eventsSince(_ date: Date) -> [PauseEvent] {
        recentEvents.filter { $0.triggeredAt >= date }
    }

    func load() async {
        let rules = await ruleRepository.rules()
        let events = await eventRepository.events(from: nil, to: nil)
        let loaded = PausesOverviewState(
            summary: calculator.summary(from: events),
            reclaimedTimeText: LocktyDurationFormatter.abbreviated(TimeInterval(events.filter { $0.decision == .abandoned }.count) * 4 * 60),
            rules: rules.map { rule in
                let ruleEvents = events.filter { $0.pauseRuleID == rule.id }
                let summary = calculator.summary(from: ruleEvents)
                return PauseRuleSummaryState(
                    id: rule.id,
                    name: rule.displayName,
                    flow: rule.steps.map(\.title).joined(separator: " -> "),
                    successRate: summary.successRateValue.map { "\($0)% success" } ?? "No decisions",
                    stopped: summary.stoppedCount,
                    continued: summary.continuedCount
                )
            }
        )

        withAnimation(.smooth(duration: 0.28)) {
            state = loaded
            recentEvents = events
        }
    }
}
