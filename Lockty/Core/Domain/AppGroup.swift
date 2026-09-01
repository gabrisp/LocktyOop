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
                name: "Distrayendo",
                selectionScope: .distracting
            )
        ]
    }

    nonisolated static func selectionScope(for id: UUID) -> ScreenTimeSelectionScope? {
        builtIn.first { $0.id == id }?.selectionScope
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
            "Detects distracting apps without a friction."
        case .medium:
            "Uses a friction when AutoFocus intervenes."
        case .high:
            "Uses the configured friction with the strongest intervention."
        }
    }
}

nonisolated struct AutoFocusConfiguration: Codable, Hashable {
    var distractingApplicationIDs: Set<AppIdentity.ID>
    var interventionLevel: AutoFocusInterventionLevel
    var frictionID: UUID?
    var cooldownMinutes: Int
    var updatedAt: Date

    init(
        distractingApplicationIDs: Set<AppIdentity.ID> = [],
        interventionLevel: AutoFocusInterventionLevel = .medium,
        frictionID: UUID? = nil,
        cooldownMinutes: Int = 60,
        updatedAt: Date = Date()
    ) {
        self.distractingApplicationIDs = distractingApplicationIDs
        self.interventionLevel = interventionLevel
        self.frictionID = frictionID
        self.cooldownMinutes = cooldownMinutes
        self.updatedAt = updatedAt
    }

    static let `default` = AutoFocusConfiguration()
}
