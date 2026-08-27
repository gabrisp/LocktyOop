import Foundation

nonisolated enum BreakTrigger: String, Codable, CaseIterable, Hashable, Identifiable {
    case manual
    case nfc
    case location

    var id: String { rawValue }
}

nonisolated struct BreakPolicy: Codable, Hashable {
    var maximumBreaks: Int
    var maximumDuration: TimeInterval
    var minimumInterval: TimeInterval
    var allowedTriggers: Set<BreakTrigger>

    static let none = BreakPolicy(
        maximumBreaks: 0,
        maximumDuration: 0,
        minimumInterval: 0,
        allowedTriggers: []
    )
}

nonisolated struct ActiveBreak: Codable, Hashable, Identifiable {
    let id: UUID
    var routineID: UUID
    var startedAt: Date
    var endsAt: Date
    var trigger: BreakTrigger

    init(
        id: UUID = UUID(),
        routineID: UUID,
        startedAt: Date,
        endsAt: Date,
        trigger: BreakTrigger
    ) {
        self.id = id
        self.routineID = routineID
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.trigger = trigger
    }

    var isExpired: Bool {
        Date() >= endsAt
    }
}
