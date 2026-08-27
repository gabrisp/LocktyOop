import Foundation

protocol PauseEventRepository {
    func events(from startDate: Date?, to endDate: Date?) async -> [PauseEvent]
    func save(_ event: PauseEvent) async
}

actor InMemoryPauseEventRepository: PauseEventRepository {
    private let events: [PauseEvent]

    init(referenceDate: Date = Date()) {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: referenceDate)

        events = Self.mockEvents(on: day)
    }

    func events(from startDate: Date?, to endDate: Date?) async -> [PauseEvent] {
        events.filter { event in
            let lowerBoundMatches = startDate.map { event.triggeredAt >= $0 } ?? true
            let upperBoundMatches = endDate.map { event.triggeredAt < $0 } ?? true
            return lowerBoundMatches && upperBoundMatches
        }
    }

    func save(_ event: PauseEvent) async {}

    private static func mockEvents(on day: Date) -> [PauseEvent] {
        var values: [PauseEvent] = []

        values.append(contentsOf: repeatedEvents(
            count: 93,
            rule: .mockInstagram,
            day: day,
            startingHour: 8,
            decision: .abandoned
        ))
        values.append(contentsOf: repeatedEvents(
            count: 33,
            rule: .mockInstagram,
            day: day,
            startingHour: 15,
            decision: .continued
        ))
        values.append(contentsOf: repeatedEvents(
            count: 51,
            rule: .mockTikTok,
            day: day,
            startingHour: 10,
            decision: .abandoned
        ))
        values.append(contentsOf: repeatedEvents(
            count: 12,
            rule: .mockTikTok,
            day: day,
            startingHour: 19,
            decision: .continued
        ))
        values.append(contentsOf: repeatedEvents(
            count: 39,
            rule: .mockX,
            day: day,
            startingHour: 11,
            decision: .abandoned
        ))
        values.append(contentsOf: repeatedEvents(
            count: 36,
            rule: .mockX,
            day: day,
            startingHour: 21,
            decision: .continued
        ))

        return values
    }

    private static func repeatedEvents(
        count: Int,
        rule: PauseRule,
        day: Date,
        startingHour: Int,
        decision: PauseDecision
    ) -> [PauseEvent] {
        let calendar = Calendar.current

        return (0..<count).map { index in
            let minuteOffset = index * 13
            let triggeredAt = calendar.date(
                byAdding: .minute,
                value: minuteOffset,
                to: calendar.date(bySettingHour: startingHour, minute: index % 55, second: 0, of: day) ?? day
            ) ?? day

            return PauseEvent(
                id: UUID(),
                pauseRuleID: rule.id,
                application: rule.application,
                triggeredAt: triggeredAt,
                completedAt: triggeredAt.addingTimeInterval(decision == .interrupted ? 18 : 24),
                intention: intention(for: decision, applicationName: rule.application.displayName, index: index),
                decision: decision,
                allowanceDuration: decision == .continued ? rule.allowanceDuration : nil,
                actualUsageDuration: decision == .continued ? TimeInterval(90 + (index % 5) * 42) : nil
            )
        }
    }

    private static func intention(
        for decision: PauseDecision,
        applicationName: String,
        index: Int
    ) -> String? {
        guard decision == .continued else { return nil }

        let samples = [
            "Reply to Marta",
            "Check the uploaded post",
            "Open one specific message",
            "Find a saved reference"
        ]
        return "\(samples[index % samples.count]) on \(applicationName)"
    }
}
