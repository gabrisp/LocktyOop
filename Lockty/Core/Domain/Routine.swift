import Foundation

struct Routine: Codable, Hashable, Identifiable {
    let id: UUID
    var name: String
    var icon: String?
    var colorHex: String?
    var mode: RoutineMode
    var triggers: [RoutineTrigger]
    var blockedApplications: Set<AppIdentity.ID>
    var blockedDomains: Set<String>
    var tasks: [RoutineTask]
    var breakPolicy: BreakPolicy
    var allowsPauseDuringStrictMode: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        icon: String? = nil,
        colorHex: String? = nil,
        mode: RoutineMode,
        triggers: [RoutineTrigger],
        blockedApplications: Set<AppIdentity.ID>,
        blockedDomains: Set<String>,
        tasks: [RoutineTask],
        breakPolicy: BreakPolicy,
        allowsPauseDuringStrictMode: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.mode = mode
        self.triggers = triggers
        self.blockedApplications = blockedApplications
        self.blockedDomains = blockedDomains
        self.tasks = tasks
        self.breakPolicy = breakPolicy
        self.allowsPauseDuringStrictMode = allowsPauseDuringStrictMode
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension Routine {
    static let mockDeepWork = Routine(
        name: "Deep Work",
        icon: "brain.head.profile",
        mode: .strict,
        triggers: [.manual],
        blockedApplications: ["instagram", "youtube"],
        blockedDomains: ["instagram.com", "youtube.com"],
        tasks: [
            RoutineTask(title: "Read 10 minutes", icon: "book", order: 0),
            RoutineTask(title: "Journal", icon: "pencil", order: 1),
            RoutineTask(title: "Stretch", icon: "figure.cooldown", order: 2, isOptional: true)
        ],
        breakPolicy: BreakPolicy(
            maximumBreaks: 2,
            maximumDuration: 10 * 60,
            minimumInterval: 30 * 60,
            allowedTriggers: [.manual, .nfc]
        )
    )

    static let mockMorning = Routine(
        name: "Morning Reset",
        icon: "sun.max",
        mode: .normal,
        triggers: [.manual],
        blockedApplications: ["instagram", "youtube", "whatsapp"],
        blockedDomains: ["x.com"],
        tasks: [
            RoutineTask(title: "Pray", icon: "hands.sparkles", order: 0),
            RoutineTask(title: "Coffee", icon: "cup.and.saucer", order: 1),
            RoutineTask(title: "Meditate", icon: "figure.mind.and.body", order: 2)
        ],
        breakPolicy: .none
    )
}
