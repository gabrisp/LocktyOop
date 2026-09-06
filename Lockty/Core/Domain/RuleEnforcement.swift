import FamilyControls
import Foundation
import ManagedSettings

/// What a rule has spent today.
///
/// Kept per day rather than as a running total: every limit in `RuleKind` resets, and a
/// counter with no day attached to it cannot tell "three opens so far today" from "three
/// opens since you installed the app".
nonisolated struct RuleEnforcementRecord: Codable, Hashable {
    /// The local day this record counts for, as `yyyy-MM-dd`.
    var dayKey: String
    /// How many times the rule's apps have been opened today.
    ///
    /// Observed, not granted. Screen Time reports pickups per app per day, and that count
    /// is written here whenever a day is read -- the rule does not have to hold the apps
    /// shut in order to count them, which is what it used to do.
    var openCountUsed: Int
    /// When a `.dailyUsageLimit` rule spent its budget. Nil means it still has some.
    var usageLimitReachedAt: Date?

    init(dayKey: String, openCountUsed: Int = 0, usageLimitReachedAt: Date? = nil) {
        self.dayKey = dayKey
        self.openCountUsed = openCountUsed
        self.usageLimitReachedAt = usageLimitReachedAt
    }
}

nonisolated struct RuleEnforcementState: Codable, Hashable {
    var records: [UUID: RuleEnforcementRecord]

    init(records: [UUID: RuleEnforcementRecord] = [:]) {
        self.records = records
    }

    static let empty = RuleEnforcementState()

    /// The day key for a date, in the device's own calendar.
    ///
    /// Not `DayKey`: this has to be readable from the monitor and shield extensions,
    /// which is also why it is a plain string rather than a date that has to survive a
    /// timezone change to still mean "today".
    nonisolated static func dayKey(for date: Date = Date()) -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    /// The rule's record for today. A record left over from an earlier day reads as a
    /// fresh one, so nothing has to go round at midnight resetting counters.
    nonisolated func record(for ruleID: UUID, on date: Date = Date()) -> RuleEnforcementRecord {
        let key = Self.dayKey(for: date)
        guard let stored = records[ruleID], stored.dayKey == key else {
            return RuleEnforcementRecord(dayKey: key)
        }
        return stored
    }

    nonisolated mutating func update(
        _ ruleID: UUID,
        on date: Date = Date(),
        _ transform: (inout RuleEnforcementRecord) -> Void
    ) {
        var current = record(for: ruleID, on: date)
        transform(&current)
        records[ruleID] = current
    }

    /// Drops records for rules that no longer exist, and for days that have passed.
    nonisolated mutating func prune(keeping ruleIDs: Set<UUID>, on date: Date = Date()) {
        let key = Self.dayKey(for: date)
        records = records.filter { ruleIDs.contains($0.key) && $0.value.dayKey == key }
    }
}

extension Rule {
    /// The selection scopes that say which apps this rule covers.
    nonisolated var selectionScopes: Set<ScreenTimeSelectionScope> {
        Set([ScreenTimeSelectionScope.rule(id)] + appGroupIDs.map(ScreenTimeSelectionScope.appGroupScope))
    }

    /// Whether the rule's apps should be behind a shield right now.
    ///
    /// The three limits reach that answer in two different ways, because Screen Time
    /// only measures one of them for us:
    ///
    /// - `.dailyUsageLimit` is measured by DeviceActivity. The apps are free until the
    ///   threshold event says the day's minutes are gone, and then they are shielded for
    ///   the rest of the day.
    /// - `.openCountLimit` is counted from the report's own pickups, which are written
    ///   into the enforcement record as each day is read. The apps are free for the
    ///   opens the rule allows and shut once they are spent -- ten opens means ten
    ///   ordinary opens, not ten trips through a shield.
    ///
    ///   The cost is honesty about lag: there is no "times opened" event to subscribe
    ///   to, so the count only moves when Screen Time hands over a fresh report. The
    ///   eleventh open can happen before the block lands. The alternative was shielding
    ///   the app from the first open of the day so the shield could do the counting,
    ///   which enforces perfectly and makes "ten opens a day" mean ten interruptions.
    /// - `.sessionDurationLimit` still cannot be measured: a threshold counts across a
    ///   whole interval rather than across one sitting, so the apps stay shielded and
    ///   each trip through hands back one sitting's worth of time.
    /// - `.schedule` is a routine and is not enforced here at all.
    nonisolated func isShielding(given enforcement: RuleEnforcementState, on date: Date = Date()) -> Bool {
        guard isEnabled else { return false }

        switch kind {
        case .schedule:
            return false
        case .dailyUsageLimit:
            return enforcement.record(for: id, on: date).usageLimitReachedAt != nil
        case .openCountLimit:
            return (remainingOpens(given: enforcement, on: date) ?? 1) <= 0
        case .sessionDurationLimit:
            return true
        }
    }

    /// How many more times the shield may let the user through today, for a rule that
    /// counts opens. Nil for every other kind, which does not count them.
    nonisolated func remainingOpens(given enforcement: RuleEnforcementState, on date: Date = Date()) -> Int? {
        guard kind == .openCountLimit, let configuration = openCountLimitConfiguration else { return nil }
        let used = enforcement.record(for: id, on: date).openCountUsed
        return max(configuration.maximumOpens - used, 0)
    }

    /// The minutes one trip through the shield is worth, for the kinds that grant one.
    nonisolated var allowanceMinutesPerPass: Int? {
        switch kind {
        case .sessionDurationLimit:
            sessionDurationLimitConfiguration.map { max($0.maximumMinutesPerSession, 1) }
        case .openCountLimit:
            // Past the day's opens, the only way back in is a break -- so the length is
            // the break's, and there is none at all when the rule allows none.
            breakPolicy.isAllowed ? max(breakPolicy.durationMinutes ?? 5, 1) : nil
        case .schedule, .dailyUsageLimit:
            nil
        }
    }
}

/// Finds the limit rule that is holding a given app shut, and charges it.
///
/// Lives here rather than in a service because both sides need it: the shield action
/// extension asks it what one trip through the shield is worth (and whether there is one
/// left at all), and the app charges the counter once the unlock is actually granted.
nonisolated struct RuleShieldLookup {
    let appGroupStore: AppGroupStore
    let selectionStore: ScreenTimeSelectionStore

    init(
        appGroupStore: AppGroupStore = AppGroupStore(),
        selectionStore: ScreenTimeSelectionStore = ScreenTimeSelectionStore()
    ) {
        self.appGroupStore = appGroupStore
        self.selectionStore = selectionStore
    }

    /// The enabled limit rule covering this app, if there is one.
    ///
    /// Matched on the app's own token. A rule that covers the app only through a whole
    /// category cannot be matched here -- ManagedSettings hands out category tokens that
    /// cannot be expanded into the apps inside them -- so such an app falls back to the
    /// standard unlock flow rather than to a wrong rule's counter.
    func limitingRule(for token: ApplicationToken) -> Rule? {
        let rules = appGroupStore.loadStoredRules().filter { $0.isEnabled && $0.kind != .schedule }
        guard !rules.isEmpty else { return nil }

        let appID = AppIdentity.ID(token: token)
        return rules.first { rule in
            if rule.blockedApplications.contains(appID) { return true }
            return selectionStore
                .mergedSelection(scopes: rule.selectionScopes)
                .applicationTokens
                .contains(token)
        }
    }

    /// What the shield should do about this app, when a limit rule covers it.
    enum Decision: Equatable {
        /// No limit rule covers the app; whatever else shields it decides.
        case notLimited
        /// One trip through is available, worth this many seconds.
        case allow(ruleID: UUID, allowanceDuration: TimeInterval)
        /// The rule has nothing left to give today.
        case exhausted(ruleID: UUID, ruleName: String)
    }

    /// The same answer, for a rule already known by id.
    ///
    /// The shield action starts from a token because that is all it has; the app starts
    /// from the request the shield wrote, which names the rule outright. Asking by token
    /// there would mean matching an app back to a rule that has already been matched.
    func decision(forRule ruleID: UUID, on date: Date = Date()) -> Decision {
        guard let rule = appGroupStore.loadStoredRules().first(where: { $0.id == ruleID }) else {
            return .notLimited
        }
        return decision(for: rule, on: date)
    }

    func decision(for token: ApplicationToken, on date: Date = Date()) -> Decision {
        guard let rule = limitingRule(for: token) else { return .notLimited }
        return decision(for: rule, on: date)
    }

    private func decision(for rule: Rule, on date: Date) -> Decision {
        let enforcement = appGroupStore.loadRuleEnforcementState()

        // Out of opens. A break is the way back in when the rule offers one, and there is
        // simply no way in when it does not -- which is the difference between "ten opens
        // and then earn the next one" and "ten opens and that is the day".
        if let remaining = rule.remainingOpens(given: enforcement, on: date), remaining <= 0 {
            guard rule.breakPolicy.isAllowed, let minutes = rule.allowanceMinutesPerPass else {
                return .exhausted(ruleID: rule.id, ruleName: rule.name)
            }
            return .allow(ruleID: rule.id, allowanceDuration: TimeInterval(minutes * 60))
        }

        // A daily-usage rule that has spent its budget is shut until tomorrow; there is
        // no per-pass allowance to hand out for it.
        if rule.kind == .dailyUsageLimit {
            return enforcement.record(for: rule.id, on: date).usageLimitReachedAt == nil
                ? .notLimited
                : .exhausted(ruleID: rule.id, ruleName: rule.name)
        }

        guard let minutes = rule.allowanceMinutesPerPass else { return .notLimited }
        return .allow(ruleID: rule.id, allowanceDuration: TimeInterval(minutes * 60))
    }

    /// Records what the day's report says about a rule's opens.
    ///
    /// Written by the app as each day is read, from the pickups Screen Time reports per
    /// app. It replaces rather than adds: this is an observation of the whole day, not an
    /// event, so running it twice must not count the same opens twice.
    ///
    /// This used to be `chargePass`, incremented when an unlock was granted -- which only
    /// worked because every open went through the shield. It no longer does.
    func recordObservedOpens(_ opens: Int, ruleID: UUID, on date: Date = Date()) {
        let stored = appGroupStore.loadRuleEnforcementState().record(for: ruleID, on: date)
        guard stored.openCountUsed != opens else { return }

        try? appGroupStore.updateRuleEnforcementState { state in
            state.update(ruleID, on: date) { record in
                record.openCountUsed = opens
            }
        }
    }
}
