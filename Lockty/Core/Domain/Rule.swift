import Foundation

nonisolated enum RuleKind: String, Codable, CaseIterable, Hashable, Identifiable {
    case schedule
    case openCountLimit
    case dailyUsageLimit
    case sessionDurationLimit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .schedule:
            "Schedule"
        case .openCountLimit:
            "Open Count"
        case .dailyUsageLimit:
            "Daily Usage"
        case .sessionDurationLimit:
            "Session Duration"
        }
    }
}

nonisolated enum RuleResetPeriod: String, Codable, CaseIterable, Hashable, Identifiable {
    case daily
    case rolling24Hours

    var id: String { rawValue }
}

nonisolated struct RuleBreakPolicy: Codable, Hashable {
    var isAllowed: Bool
    var durationMinutes: Int?
    var maximumBreaks: Int
    var resetPeriod: RuleResetPeriod
    var cooldownMinutes: Int
    var allowedTriggers: Set<BreakTrigger>
    var requiredFrictionID: UUID?
    var frictionPolicy: RoutinePausePolicy

    init(
        isAllowed: Bool = false,
        durationMinutes: Int? = nil,
        maximumBreaks: Int = 0,
        resetPeriod: RuleResetPeriod = .daily,
        cooldownMinutes: Int = 0,
        allowedTriggers: Set<BreakTrigger> = [],
        requiredFrictionID: UUID? = nil,
        frictionPolicy: RoutinePausePolicy = .off
    ) {
        self.isAllowed = isAllowed
        self.durationMinutes = durationMinutes
        self.maximumBreaks = maximumBreaks
        self.resetPeriod = resetPeriod
        self.cooldownMinutes = cooldownMinutes
        self.allowedTriggers = allowedTriggers
        self.requiredFrictionID = requiredFrictionID
        self.frictionPolicy = frictionPolicy
    }

    init(
        legacyBreakPolicy: BreakPolicy,
        requiredFrictionID: UUID?,
        frictionPolicy: RoutinePausePolicy
    ) {
        self.init(
            isAllowed: legacyBreakPolicy.maximumBreaks > 0,
            durationMinutes: legacyBreakPolicy.maximumDuration > 0
                ? max(1, Int(legacyBreakPolicy.maximumDuration / 60))
                : nil,
            maximumBreaks: legacyBreakPolicy.maximumBreaks,
            resetPeriod: .daily,
            cooldownMinutes: max(0, Int(legacyBreakPolicy.minimumInterval / 60)),
            allowedTriggers: legacyBreakPolicy.allowedTriggers,
            requiredFrictionID: requiredFrictionID,
            frictionPolicy: frictionPolicy
        )
    }

    var legacyBreakPolicy: BreakPolicy {
        guard isAllowed else { return .none }
        return BreakPolicy(
            maximumBreaks: maximumBreaks,
            maximumDuration: TimeInterval(max(durationMinutes ?? 0, 0) * 60),
            minimumInterval: TimeInterval(max(cooldownMinutes, 0) * 60),
            allowedTriggers: allowedTriggers
        )
    }
}

nonisolated struct ScheduleRuleConfiguration: Codable, Hashable {
    var icon: String?
    var color: RoutineColor
    var mode: RoutineMode
    var triggers: [RoutineTrigger]
    var tasks: [RoutineTask]
    var startAlarmEnabled: Bool
    var allowsBreakDuringStrictMode: Bool
}

nonisolated struct OpenCountLimitRuleConfiguration: Codable, Hashable {
    var maximumOpens: Int
    var windowHours: Int
}

nonisolated struct DailyUsageLimitRuleConfiguration: Codable, Hashable {
    var maximumMinutesPerDay: Int
    var resetPeriod: RuleResetPeriod
}

nonisolated struct SessionDurationLimitRuleConfiguration: Codable, Hashable {
    var maximumMinutesPerSession: Int
}

nonisolated struct Rule: Codable, Hashable, Identifiable {
    let id: UUID
    var name: String
    var isEnabled: Bool
    var kind: RuleKind
    var appGroupIDs: Set<UUID>
    var blockedApplications: Set<AppIdentity.ID>
    var blockedDomains: Set<String>
    /// The device-level switches this rule throws while it is shielding.
    var contentRestrictions: ContentRestrictions
    var scheduleConfiguration: ScheduleRuleConfiguration?
    var openCountLimitConfiguration: OpenCountLimitRuleConfiguration?
    var dailyUsageLimitConfiguration: DailyUsageLimitRuleConfiguration?
    var sessionDurationLimitConfiguration: SessionDurationLimitRuleConfiguration?
    var breakPolicy: RuleBreakPolicy
    var createdAt: Date
    var updatedAt: Date

    // Written by hand for one key, so a rule saved before `contentRestrictions` existed
    // still decodes instead of throwing on every rule in the library.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        kind = try container.decode(RuleKind.self, forKey: .kind)
        appGroupIDs = try container.decodeIfPresent(Set<UUID>.self, forKey: .appGroupIDs) ?? []
        blockedApplications = try container.decodeIfPresent(Set<AppIdentity.ID>.self, forKey: .blockedApplications) ?? []
        blockedDomains = try container.decodeIfPresent(Set<String>.self, forKey: .blockedDomains) ?? []
        contentRestrictions = try container.decodeIfPresent(ContentRestrictions.self, forKey: .contentRestrictions) ?? .none
        scheduleConfiguration = try container.decodeIfPresent(ScheduleRuleConfiguration.self, forKey: .scheduleConfiguration)
        openCountLimitConfiguration = try container.decodeIfPresent(OpenCountLimitRuleConfiguration.self, forKey: .openCountLimitConfiguration)
        dailyUsageLimitConfiguration = try container.decodeIfPresent(DailyUsageLimitRuleConfiguration.self, forKey: .dailyUsageLimitConfiguration)
        sessionDurationLimitConfiguration = try container.decodeIfPresent(SessionDurationLimitRuleConfiguration.self, forKey: .sessionDurationLimitConfiguration)
        breakPolicy = try container.decodeIfPresent(RuleBreakPolicy.self, forKey: .breakPolicy) ?? RuleBreakPolicy()
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        kind: RuleKind,
        appGroupIDs: Set<UUID> = [],
        blockedApplications: Set<AppIdentity.ID> = [],
        blockedDomains: Set<String> = [],
        contentRestrictions: ContentRestrictions = .none,
        scheduleConfiguration: ScheduleRuleConfiguration? = nil,
        openCountLimitConfiguration: OpenCountLimitRuleConfiguration? = nil,
        dailyUsageLimitConfiguration: DailyUsageLimitRuleConfiguration? = nil,
        sessionDurationLimitConfiguration: SessionDurationLimitRuleConfiguration? = nil,
        breakPolicy: RuleBreakPolicy = RuleBreakPolicy(),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.kind = kind
        self.appGroupIDs = appGroupIDs
        self.blockedApplications = blockedApplications
        self.blockedDomains = blockedDomains
        self.contentRestrictions = contentRestrictions
        self.scheduleConfiguration = scheduleConfiguration
        self.openCountLimitConfiguration = openCountLimitConfiguration
        self.dailyUsageLimitConfiguration = dailyUsageLimitConfiguration
        self.sessionDurationLimitConfiguration = sessionDurationLimitConfiguration
        self.breakPolicy = breakPolicy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension Rule {
    init(routine: Routine) {
        self.init(
            id: routine.id,
            name: routine.name,
            isEnabled: true,
            kind: .schedule,
            appGroupIDs: routine.appGroupIDs,
            blockedApplications: routine.blockedApplications,
            blockedDomains: routine.blockedDomains,
            scheduleConfiguration: ScheduleRuleConfiguration(
                icon: routine.icon,
                color: routine.color,
                mode: routine.mode,
                triggers: routine.triggers,
                tasks: routine.tasks,
                startAlarmEnabled: routine.startAlarmEnabled,
                allowsBreakDuringStrictMode: routine.allowsPauseDuringStrictMode
            ),
            breakPolicy: RuleBreakPolicy(
                legacyBreakPolicy: routine.breakPolicy,
                requiredFrictionID: routine.pauseFlowID,
                frictionPolicy: routine.pausePolicy
            ),
            createdAt: routine.createdAt,
            updatedAt: routine.updatedAt
        )
    }

    var routineBridge: Routine? {
        guard kind == .schedule, let scheduleConfiguration else { return nil }
        return Routine(
            id: id,
            name: name,
            icon: scheduleConfiguration.icon,
            color: scheduleConfiguration.color,
            mode: scheduleConfiguration.mode,
            triggers: scheduleConfiguration.triggers,
            appGroupIDs: appGroupIDs,
            blockedApplications: blockedApplications,
            blockedDomains: blockedDomains,
            tasks: scheduleConfiguration.tasks,
            startAlarmEnabled: scheduleConfiguration.startAlarmEnabled,
            breakPolicy: breakPolicy.legacyBreakPolicy,
            pauseFlowID: breakPolicy.requiredFrictionID,
            pausePolicy: breakPolicy.frictionPolicy,
            allowsPauseDuringStrictMode: scheduleConfiguration.allowsBreakDuringStrictMode,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
