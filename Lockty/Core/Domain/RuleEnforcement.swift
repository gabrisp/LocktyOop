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
    /// Passes through the shield a `.openCountLimit` rule has already granted today.
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
    /// - `.openCountLimit` and `.sessionDurationLimit` cannot be measured that way --
    ///   there is no "times opened" event, and a threshold counts across a whole interval
    ///   rather than across one sitting. Both are enforced from the other side instead:
    ///   the apps stay shielded, and each trip through the shield hands back a limited
    ///   allowance. The shield is the meter.
    /// - `.schedule` is a routine and is not enforced here at all.
    nonisolated func isShielding(given enforcement: RuleEnforcementState, on date: Date = Date()) -> Bool {
        guard isEnabled else { return false }

        switch kind {
        case .schedule:
            return false
        case .dailyUsageLimit:
            return enforcement.record(for: id, on: date).usageLimitReachedAt != nil
        case .openCountLimit, .sessionDurationLimit:
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
            // An open is a sitting, not an instant. Without a length of its own the app
            // would re-shield the moment it came to the front and the open would be
            // spent on nothing.
            15
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

    func decision(for token: ApplicationToken, on date: Date = Date()) -> Decision {
        guard let rule = limitingRule(for: token) else { return .notLimited }

        let enforcement = appGroupStore.loadRuleEnforcementState()

        if let remaining = rule.remainingOpens(given: enforcement, on: date), remaining <= 0 {
            return .exhausted(ruleID: rule.id, ruleName: rule.name)
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

    /// Charges one pass to the rule, if it is one that counts them.
    ///
    /// Called when the unlock is granted, not when it is asked for: a flow the user
    /// started and then walked away from must not cost them an open.
    func chargePass(ruleID: UUID, on date: Date = Date()) {
        guard let rule = appGroupStore.loadStoredRules().first(where: { $0.id == ruleID }),
              rule.kind == .openCountLimit
        else { return }

        try? appGroupStore.updateRuleEnforcementState { state in
            state.update(ruleID, on: date) { record in
                record.openCountUsed += 1
            }
        }
    }
}
