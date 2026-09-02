import Foundation

nonisolated enum BreakTrigger: String, Codable, CaseIterable, Hashable, Identifiable {
    case manual
    case nfc
    case location

    var id: String { rawValue }
}

nonisolated struct BreakPolicy: Codable, Hashable {
    /// How many breaks a routine allows, where `unlimitedBreaks` means it never runs out.
    ///
    /// `Int.max` rather than a negative flag or an optional: zero already means "no
    /// breaks at all" and is read that way in half a dozen places, and every count the
    /// enforcement does is a `<` against this number. A sentinel that is simply enormous
    /// makes "unlimited" fall out of the arithmetic that is already there instead of
    /// needing a special case at each site.
    static let unlimitedBreaks = Int.max

    var maximumBreaks: Int
    var maximumDuration: TimeInterval
    var minimumInterval: TimeInterval
    var allowedTriggers: Set<BreakTrigger>

    var allowsUnlimitedBreaks: Bool { maximumBreaks == Self.unlimitedBreaks }

    /// How a count of breaks reads. The infinity sign rather than the word, because it
    /// sits where a numeral sits and has to be as short as one.
    static func label(forMaximumBreaks count: Int) -> String {
        count == unlimitedBreaks ? "∞" : "\(count)"
    }

    static let none = BreakPolicy(
        maximumBreaks: 0,
        maximumDuration: 0,
        minimumInterval: 0,
        allowedTriggers: []
    )
}

nonisolated enum BreakAvailability: Hashable {
    case available
    case unavailable(BreakUnavailableState)
}

nonisolated struct BreakUnavailableState: Hashable, Identifiable {
    let id: UUID
    var title: String
    var message: String
    /// When the cooldown lets go. Carried as a date rather than as a count of minutes
    /// so the sheet can tick down against it in real time instead of showing a number
    /// that was rounded up once, when the sheet opened, and then stood still.
    var retryAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        message: String,
        retryAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.retryAt = retryAt
    }
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
