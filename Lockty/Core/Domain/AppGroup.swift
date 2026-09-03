import Foundation

nonisolated struct AppGroup: Codable, Hashable, Identifiable {
    let id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

nonisolated struct ReusableAppGroupDefinition: Codable, Hashable, Identifiable {
    let id: UUID
    var name: String
    var selectionScope: ScreenTimeSelectionScope
}

extension ReusableAppGroupDefinition {
    /// Built-in reusable groups that are backed by a selection scope, not by a saved
    /// user AppGroup row. Add new suggested/system groups here instead of teaching the
    /// shield about one UUID at a time.
    nonisolated static var builtIn: [ReusableAppGroupDefinition] {
        [
            ReusableAppGroupDefinition(
                id: UUID(uuidString: "00000000-0000-0000-0000-00000000D157")!,
                name: "Distracting",
                selectionScope: .distracting
            ),
            ReusableAppGroupDefinition(
                id: ReusableAppGroupDefinition.alwaysAllowedID,
                name: "Always Allowed",
                selectionScope: .alwaysAllowed
            )
        ]
    }

    /// The group nothing may block.
    ///
    /// Fixed rather than generated so the shield, the extensions and the editors all mean
    /// the same folder without having to be told which one it is.
    nonisolated static let alwaysAllowedID = UUID(uuidString: "00000000-0000-0000-0000-00000000A11D")!

    nonisolated static func selectionScope(for id: UUID) -> ScreenTimeSelectionScope? {
        builtIn.first { $0.id == id }?.selectionScope
    }

    /// Groups that can be picked as something to *block*.
    ///
    /// Always Allowed is not one of them: it is the opposite instruction, and offering it
    /// in a "choose what to block" list would let someone build a rule that contradicts
    /// itself.
    nonisolated static var selectableAsRestriction: [ReusableAppGroupDefinition] {
        builtIn.filter { $0.id != alwaysAllowedID }
    }
}

nonisolated enum AutoFocusInterventionLevel: String, Codable, CaseIterable, Hashable, Identifiable {
    case low
    case medium
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low:
            "Low"
        case .medium:
            "Medium"
        case .high:
            "High"
        }
    }

    var summary: String {
        switch self {
        case .low:
            "After 45 minutes, at most every two hours."
        case .medium:
            "After 25 minutes, at most every hour."
        case .high:
            "After 12 minutes, at most every half hour."
        }
    }
}

nonisolated struct AutoFocusConfiguration: Codable, Hashable {
    var distractingApplicationIDs: Set<AppIdentity.ID>
    var interventionLevel: AutoFocusInterventionLevel
    var frictionID: UUID?
    /// Whether it says anything at all.
    ///
    /// The only kind of intervention there is: a screen in front of an app is allowed
    /// only against a block the person set up, and this one is noticed rather than
    /// chosen. The switch exists so the apps can stay listed -- they are what the
    /// breakdown calls unproductive -- while the interruptions are off.
    var notificationsEnabled: Bool
    var cooldownMinutes: Int
    var updatedAt: Date

    init(
        distractingApplicationIDs: Set<AppIdentity.ID> = [],
        interventionLevel: AutoFocusInterventionLevel = .medium,
        frictionID: UUID? = nil,
        notificationsEnabled: Bool = true,
        cooldownMinutes: Int = 60,
        updatedAt: Date = Date()
    ) {
        self.distractingApplicationIDs = distractingApplicationIDs
        self.interventionLevel = interventionLevel
        self.frictionID = frictionID
        self.notificationsEnabled = notificationsEnabled
        self.cooldownMinutes = cooldownMinutes
        self.updatedAt = updatedAt
    }

    static let `default` = AutoFocusConfiguration()

    // Tolerant, so a configuration written before the switch existed keeps working and
    // arrives with the interventions on -- which is what it was doing.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        distractingApplicationIDs = try container.decodeIfPresent(Set<AppIdentity.ID>.self, forKey: .distractingApplicationIDs) ?? []
        interventionLevel = try container.decodeIfPresent(AutoFocusInterventionLevel.self, forKey: .interventionLevel) ?? .medium
        frictionID = try container.decodeIfPresent(UUID.self, forKey: .frictionID)
        notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
        cooldownMinutes = try container.decodeIfPresent(Int.self, forKey: .cooldownMinutes) ?? 60
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}
