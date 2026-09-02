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
    /// The device-level switches this routine throws while it runs.
    var contentRestrictions: ContentRestrictions
    /// What Strict Mode closes, when this routine is strict. Ignored otherwise.
    var strictGuards: StrictModeGuards
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
        contentRestrictions: ContentRestrictions = .none,
        strictGuards: StrictModeGuards = StrictModeGuards(),
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
        self.contentRestrictions = contentRestrictions
        self.strictGuards = strictGuards
        self.tasks = tasks
        self.startAlarmEnabled = startAlarmEnabled
        self.breakPolicy = breakPolicy
        self.pauseFlowID = pauseFlowID
        self.pausePolicy = pausePolicy
        self.allowsPauseDuringStrictMode = allowsPauseDuringStrictMode
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // Written by hand for one key: routines saved before `contentRestrictions` existed
    // have no entry for it, and the synthesized decoder throws `keyNotFound` on every
    // one of them -- which reads as the routine library having emptied itself.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        color = try container.decode(RoutineColor.self, forKey: .color)
        mode = try container.decode(RoutineMode.self, forKey: .mode)
        triggers = try container.decode([RoutineTrigger].self, forKey: .triggers)
        appGroupIDs = try container.decodeIfPresent(Set<UUID>.self, forKey: .appGroupIDs) ?? []
        blockedApplications = try container.decode(Set<AppIdentity.ID>.self, forKey: .blockedApplications)
        blockedDomains = try container.decode(Set<String>.self, forKey: .blockedDomains)
        contentRestrictions = try container.decodeIfPresent(ContentRestrictions.self, forKey: .contentRestrictions) ?? .none
        // `.legacy`, not the new default: a strict routine written before this existed
        // only prevented editing, and it does not get new restrictions retroactively.
        strictGuards = try container.decodeIfPresent(StrictModeGuards.self, forKey: .strictGuards) ?? .legacy
        tasks = try container.decode([RoutineTask].self, forKey: .tasks)
        startAlarmEnabled = try container.decodeIfPresent(Bool.self, forKey: .startAlarmEnabled) ?? false
        breakPolicy = try container.decode(BreakPolicy.self, forKey: .breakPolicy)
        pauseFlowID = try container.decodeIfPresent(UUID.self, forKey: .pauseFlowID)
        pausePolicy = try container.decodeIfPresent(RoutinePausePolicy.self, forKey: .pausePolicy) ?? .off
        allowsPauseDuringStrictMode = try container.decodeIfPresent(Bool.self, forKey: .allowsPauseDuringStrictMode) ?? true
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
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
