import Foundation

/// Rules that have been put on hold, and until when.
///
/// Kept in the App Group beside the enforcement counters rather than on the rule itself,
/// for two reasons. A pause is not part of what a rule *is* -- it is a fact about right
/// now, like the count of opens spent today -- and the monitor extension has to be able
/// to read it with the app closed, which is the only place a scheduled routine ever
/// starts. It also means putting a rule on hold does not rewrite the rule, so nothing
/// about it can be lost in the round trip.
nonisolated struct RulePauseState: Codable, Hashable {
    /// Rule id to the moment the hold ends.
    var pausedUntil: [UUID: Date]

    init(pausedUntil: [UUID: Date] = [:]) {
        self.pausedUntil = pausedUntil
    }

    static let empty = RulePauseState()

    /// The longest a rule may be held. A month is already a long time to have decided
    /// something you set up on purpose should not run; past that it is not a pause, it is
    /// a rule you no longer want, and there is a button for that.
    static let maximumPause: TimeInterval = 30 * 24 * 60 * 60

    nonisolated func isPaused(_ ruleID: UUID, on date: Date = Date()) -> Bool {
        guard let until = pausedUntil[ruleID] else { return false }
        return until > date
    }

    /// When the hold on this rule ends, or nil if it is not held.
    nonisolated func pauseEnd(for ruleID: UUID, on date: Date = Date()) -> Date? {
        guard let until = pausedUntil[ruleID], until > date else { return nil }
        return until
    }

    nonisolated mutating func pause(_ ruleID: UUID, until date: Date, now: Date = Date()) {
        pausedUntil[ruleID] = min(date, now.addingTimeInterval(Self.maximumPause))
    }

    nonisolated mutating func resume(_ ruleID: UUID) {
        pausedUntil[ruleID] = nil
    }

    /// Drops holds that have run out and rules that no longer exist.
    nonisolated mutating func prune(keeping ruleIDs: Set<UUID>, on date: Date = Date()) {
        pausedUntil = pausedUntil.filter { ruleIDs.contains($0.key) && $0.value > date }
    }
}

/// The lengths the picker offers.
///
/// A list rather than a free number: nobody wants to dial 4 hours and 12 minutes, and the
/// steps are the ones people actually mean -- the rest of today, tomorrow, a week off.
nonisolated enum RulePauseDuration: Int, CaseIterable, Identifiable {
    case oneHour = 1
    case twoHours = 2
    case fourHours = 4
    case eightHours = 8
    case oneDay = 24
    case twoDays = 48
    case threeDays = 72
    case oneWeek = 168
    case twoWeeks = 336
    case thirtyDays = 720

    var id: Int { rawValue }

    var duration: TimeInterval { TimeInterval(rawValue) * 3600 }

    var title: String {
        switch self {
        case .oneHour: "1 hour"
        case .twoHours: "2 hours"
        case .fourHours: "4 hours"
        case .eightHours: "8 hours"
        case .oneDay: "1 day"
        case .twoDays: "2 days"
        case .threeDays: "3 days"
        case .oneWeek: "1 week"
        case .twoWeeks: "2 weeks"
        case .thirtyDays: "30 days"
        }
    }
}
