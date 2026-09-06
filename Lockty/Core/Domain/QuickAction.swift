import Foundation

/// One thing the plus button can do.
///
/// The panel behind the plus is a shortcut bar, not a menu: which shortcuts are on it is
/// the person's own decision, so an action is stored rather than hard-coded into the view
/// and the list is a list, not a switch.
///
/// A kind and, for the one that needs it, what it is about. Logging an objective is the
/// only action that is about something in particular -- everything else is a door, and a
/// door needs no argument.
nonisolated struct QuickAction: Codable, Hashable, Identifiable {
    nonisolated enum Kind: String, Codable, CaseIterable, Hashable {
        /// Doors: each opens the editor for a new one of something.
        case newRoutine
        case newLimit
        case newObjective
        case newFriction
        /// Starting a routine now, chosen from the ones there are.
        case startRoutine
        /// One objective, logged where you stand: a step added, or a yes flipped.
        case logObjective
        /// A shield put up on the spot: a length of time, what it holds, and it starts.
        /// Not a rule saved anywhere -- decided in one go and gone when it ends.
        case quickBlock

        var title: String {
            switch self {
            case .newRoutine: "New mode"
            case .newLimit: "New limit"
            case .newObjective: "New objective"
            case .newFriction: "New friction"
            case .startRoutine: "Start a mode"
            case .logObjective: "Log objective"
            case .quickBlock: "Shield"
            }
        }

        var symbolName: String {
            switch self {
            case .newRoutine: "moon.zzz"
            case .newLimit: "hourglass"
            case .newObjective: "target"
            case .newFriction: "hand.raised"
            case .startRoutine: "play.circle"
            case .logObjective: "plus.circle"
            case .quickBlock: "shield"
            }
        }

        /// Whether one of these can sit on the panel more than once.
        ///
        /// The two that are about something in particular. Two tiles for "new limit" are
        /// two ways through the same door, but two modes started from the home screen are
        /// two different modes and two objectives logged from it are two different
        /// objectives -- refusing the second was refusing the whole point of the panel.
        var allowsDuplicates: Bool { self == .logObjective || self == .startRoutine }
    }

    var kind: Kind
    /// The objective a `.logObjective` tile is about. Nil for every other kind.
    var objectiveID: UUID?
    /// The mode a `.startRoutine` tile starts. Nil means "no mode in particular", which
    /// opens the screen with all of them instead.
    var routineID: UUID?

    var id: String {
        let subject = objectiveID ?? routineID
        return subject.map { "\(kind.rawValue)-\($0.uuidString)" } ?? kind.rawValue
    }

    init(kind: Kind, objectiveID: UUID? = nil, routineID: UUID? = nil) {
        self.kind = kind
        self.objectiveID = objectiveID
        self.routineID = routineID
    }
}

/// What is on the panel, in the order it is shown.
nonisolated struct QuickActionSet: Codable, Hashable {
    /// How many tiles the panel holds.
    ///
    /// Twelve, in three columns. Past that the panel is a screen, and a shortcut you have
    /// to look for is not a shortcut.
    static let capacity = 12

    var actions: [QuickAction]

    init(actions: [QuickAction] = QuickActionSet.default.actions) {
        self.actions = Array(actions.prefix(QuickActionSet.capacity))
    }

    /// What a phone that has never been asked shows: the four doors and starting a mode.
    static let `default` = QuickActionSet(
        actions: [
            QuickAction(kind: .startRoutine),
            QuickAction(kind: .quickBlock),
            QuickAction(kind: .newRoutine),
            QuickAction(kind: .newLimit),
            QuickAction(kind: .newObjective)
        ]
    )

    var remainingSlots: Int {
        max(QuickActionSet.capacity - actions.count, 0)
    }

    mutating func add(_ action: QuickAction) {
        guard remainingSlots > 0 else { return }
        // Never the same tile twice -- `id` carries which mode or objective it is about,
        // so this stops a second copy of one thing without stopping a second thing.
        guard !contains(action) else { return }
        guard action.kind.allowsDuplicates || !actions.contains(where: { $0.kind == action.kind }) else { return }
        actions.append(action)
    }

    mutating func remove(_ action: QuickAction) {
        actions.removeAll { $0.id == action.id }
    }

    mutating func move(_ action: QuickAction, to index: Int) {
        guard let from = actions.firstIndex(where: { $0.id == action.id }) else { return }
        let clamped = min(max(index, 0), actions.count - 1)
        guard from != clamped else { return }
        let moved = actions.remove(at: from)
        actions.insert(moved, at: clamped)
    }

    func contains(_ action: QuickAction) -> Bool {
        actions.contains { $0.id == action.id }
    }
}
