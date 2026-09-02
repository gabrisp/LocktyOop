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
    /// The furthest ahead of itself a routine may warn.
    static let maximumStartAlarmLeadMinutes = 5

    /// Repairs the one combination a routine cannot mean.
    ///
    /// A friction is the thing you go through *to take a break*, so a routine carrying
    /// one while allowing no breaks describes something that cannot happen: the shield
    /// refuses on `maximumBreaks == 0` before the friction is ever reached, and the
    /// routine reads as "Blocked" with a friction sitting in it.
    ///
    /// Applied on the way in rather than as a migration, so every routine saved while
    /// the editor let the two settings drift apart is right the moment it is read --
    /// from Core Data, from the App Group, from anywhere.
    static func reconciledBreakPolicy(
        _ policy: BreakPolicy,
        pauseFlowID: UUID?,
        pausePolicy: RoutinePausePolicy
    ) -> BreakPolicy {
        let hasFriction = pauseFlowID != nil || pausePolicy.offersPause
        guard hasFriction, policy.maximumBreaks <= 0 else { return policy }

        return BreakPolicy(
            maximumBreaks: 2,
            maximumDuration: policy.maximumDuration > 0 ? policy.maximumDuration : 5 * 60,
            minimumInterval: policy.minimumInterval > 0 ? policy.minimumInterval : 60 * 60,
            allowedTriggers: policy.allowedTriggers.isEmpty ? [.manual] : policy.allowedTriggers
        )
    }

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
    /// How many minutes before the routine starts the alarm goes off, 0 through 5.
    ///
    /// Capped at five on purpose. An alarm is a warning, and a warning half an hour early
    /// is a reminder you will have forgotten by the time it matters; five minutes is
    /// about the distance between "finish this sentence" and "you are already late".
    var startAlarmLeadMinutes: Int
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
        startAlarmLeadMinutes: Int = 0,
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
        self.startAlarmLeadMinutes = min(max(startAlarmLeadMinutes, 0), Self.maximumStartAlarmLeadMinutes)
        self.breakPolicy = Self.reconciledBreakPolicy(
            breakPolicy,
            pauseFlowID: pauseFlowID,
            pausePolicy: pausePolicy
        )
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
        startAlarmLeadMinutes = min(
            max(try container.decodeIfPresent(Int.self, forKey: .startAlarmLeadMinutes) ?? 0, 0),
            Self.maximumStartAlarmLeadMinutes
        )
        let decodedBreakPolicy = try container.decode(BreakPolicy.self, forKey: .breakPolicy)
        pauseFlowID = try container.decodeIfPresent(UUID.self, forKey: .pauseFlowID)
        pausePolicy = try container.decodeIfPresent(RoutinePausePolicy.self, forKey: .pausePolicy) ?? .off
        breakPolicy = Self.reconciledBreakPolicy(
            decodedBreakPolicy,
            pauseFlowID: pauseFlowID,
            pausePolicy: pausePolicy
        )
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
