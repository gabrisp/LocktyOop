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
