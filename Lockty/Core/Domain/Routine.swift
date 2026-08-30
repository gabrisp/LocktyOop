import Foundation

nonisolated enum RoutineColor: String, Codable, CaseIterable, Hashable, Identifiable {
    case mint
    case sky
    case amber
    case coral
    case rose
    case violet

    var id: String { rawValue }
}

struct Routine: Codable, Hashable, Identifiable {
    let id: UUID
    var name: String
    var icon: String?
    var color: RoutineColor
    var mode: RoutineMode
    var triggers: [RoutineTrigger]
    var appGroupIDs: Set<UUID>
    var blockedApplications: Set<AppIdentity.ID>
    var blockedDomains: Set<String>
    var tasks: [RoutineTask]
    var startAlarmEnabled: Bool
    var breakPolicy: BreakPolicy
    /// The saved flow this routine uses, if it has been given one. The policy below is
    /// the resolved copy: the flow can be edited or deleted afterwards, and the routine
    /// keeps working from what it was given.
    var pauseFlowID: UUID?
    /// The pause this routine offers on whatever it blocks.
    var pausePolicy: RoutinePausePolicy
    var allowsPauseDuringStrictMode: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        icon: String? = nil,
        color: RoutineColor = .mint,
        mode: RoutineMode,
        triggers: [RoutineTrigger],
        appGroupIDs: Set<UUID> = [],
        blockedApplications: Set<AppIdentity.ID>,
        blockedDomains: Set<String>,
        tasks: [RoutineTask],
        startAlarmEnabled: Bool = false,
        breakPolicy: BreakPolicy,
        pauseFlowID: UUID? = nil,
        pausePolicy: RoutinePausePolicy = .off,
        allowsPauseDuringStrictMode: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
        self.mode = mode
        self.triggers = triggers
        self.appGroupIDs = appGroupIDs
        self.blockedApplications = blockedApplications
        self.blockedDomains = blockedDomains
        self.tasks = tasks
        self.startAlarmEnabled = startAlarmEnabled
        self.breakPolicy = breakPolicy
        self.pauseFlowID = pauseFlowID
        self.pausePolicy = pausePolicy
        self.allowsPauseDuringStrictMode = allowsPauseDuringStrictMode
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var frictionID: UUID? {
        get { pauseFlowID }
        set { pauseFlowID = newValue }
    }

    var friction: RoutinePausePolicy {
        get { pausePolicy }
        set { pausePolicy = newValue }
    }
}

// Preview/test fixtures only.
#if DEBUG
extension Routine {
    static let mockDeepWork = Routine(
        name: "Deep Work",
        icon: "brain.head.profile",
        color: .sky,
        mode: .strict,
        triggers: [.manual],
        appGroupIDs: [],
        blockedApplications: ["instagram", "youtube"],
        blockedDomains: ["instagram.com", "youtube.com"],
        tasks: [
            RoutineTask(title: "Read 10 minutes", icon: "book", order: 0),
            RoutineTask(title: "Journal", icon: "pencil", order: 1),
            RoutineTask(title: "Stretch", icon: "figure.cooldown", order: 2, isOptional: true)
        ],
        startAlarmEnabled: true,
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
        color: .amber,
        mode: .normal,
        triggers: [.manual],
        appGroupIDs: [],
        blockedApplications: ["instagram", "youtube", "whatsapp"],
        blockedDomains: ["x.com"],
        tasks: [
            RoutineTask(title: "Pray", icon: "hands.sparkles", order: 0),
            RoutineTask(title: "Coffee", icon: "cup.and.saucer", order: 1),
            RoutineTask(title: "Meditate", icon: "figure.mind.and.body", order: 2)
        ],
        startAlarmEnabled: false,
        breakPolicy: .none
    )
}
#endif
