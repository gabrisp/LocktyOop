import Foundation
import ManagedSettings

/// Where one limit rule stands today.
///
/// The schedule rules already have a card of their own -- they are routines, and what
/// matters about them is when they start. A limit is the other kind of rule entirely:
/// nothing starts, nothing ends, and the only question is how much of it is left. That
/// question had no answer anywhere in the app: you set "3 opens a day" and then found out
/// where you were by being refused.
struct TodayLimitState: Identifiable, Equatable {
    enum Standing: Equatable {
        /// A budget of time being spent down. The apps are free until it runs out.
        case counting(used: String, total: String, fraction: Double)
        /// Passes through the shield, of which this many are left. The apps are shut the
        /// whole time -- that is how the passes are counted at all.
        case passes(left: Int, total: Int)
        /// Nothing left today.
        case spent
        /// A cap on each sitting rather than on the day, so there is no running total --
        /// only the length of one visit. Shut between sittings, for the same reason.
        case perSitting(String)
    }

    /// One app inside a limit, and what it has spent of the shared allowance.
    ///
    /// A daily-usage limit is one budget across several apps -- three apps and thirty
    /// minutes is thirty minutes *between them* -- so the total belongs to the rule and
    /// the split belongs here. Without the split a rule over three apps says how much is
    /// gone and never which of them spent it.
    struct AppLine: Identifiable, Equatable {
        let id: String
        let token: ApplicationToken?
        let name: String
        let detail: String
    }

    let id: UUID
    let name: String
    let standing: Standing
    /// The apps it covers, for their icons. Capped at the few that fit.
    let tokens: [ApplicationToken]
    /// What each of them spent. Empty for a rule whose apps have not been touched today.
    let apps: [AppLine]

    /// The line under the name.
    ///
    /// Counted up, like every other limit on this card: ten opens means you open the app
    /// ten times and the eleventh is refused, so the reading is "3 of 10 opens" climbing
    /// towards the cap. It used to count down -- "7 unlocks left" -- from when an open was
    /// something you spent coming through the shield; the opens are read from the day's
    /// own report now, and the app is an ordinary app until the tenth.
    var detail: String {
        switch standing {
        case .counting(let used, let total, _):
            "\(used) of \(total)"
        case .passes(let left, let total):
            "\(max(total - left, 0)) of \(total) opens"
        case .spent:
            "Blocked until tomorrow"
        case .perSitting(let text):
            text
        }
    }

    /// How full the bar is, or nil where there is nothing to fill.
    var fraction: Double? {
        switch standing {
        case .counting(_, _, let fraction): fraction
        case .passes(let left, let total): total > 0 ? Double(total - left) / Double(total) : 0
        case .spent: 1
        case .perSitting: nil
        }
    }

    var isSpent: Bool {
        if case .spent = standing { return true }
        return false
    }

    /// Whether the apps are behind the shield right now regardless of what is left.
    ///
    /// Said on the row with a padlock, because the alternative is a card that looks like
    /// everything is fine sitting above an app that will not open.
    ///
    /// Not open counts any more: those leave the apps alone until the count runs out, and
    /// a padlock on a rule with seven opens still in it was the card disagreeing with the
    /// phone. Running out is `.spent`, which is shut.
    var isHeldShut: Bool {
        switch standing {
        case .perSitting, .spent: true
        case .passes, .counting: false
        }
    }
}

enum TodayLimitBuilder {
    /// Reads every limit rule against what it has spent today.
    ///
    /// Usage is summed from the day's own app durations rather than from anything the
    /// rule keeps, because the rule keeps nothing: Screen Time tells the extension when a
    /// budget is gone and not a minute before. The figure here is therefore the same
    /// number the rest of the screen is showing, which is the point -- a card that said
    /// "32 m of 45 m" while the list above it said something else would be worse than no
    /// card at all.
    static func limits(
        rules: [Rule],
        enforcement: RuleEnforcementState,
        appUsages: [AppUsageState],
        tokensForRule: (Rule) -> [ApplicationToken],
        now: Date = Date()
    ) -> [TodayLimitState] {
        rules.compactMap { rule -> TodayLimitState? in
            guard rule.isEnabled, rule.kind != .schedule else { return nil }

            let record = enforcement.record(for: rule.id, on: now)
            // Every token the rule holds, for the matching below; only the first few are
            // drawn.
            let ruleTokens = tokensForRule(rule)
            let tokens = Array(ruleTokens.prefix(4))
            let matched = appUsages.filter { matches($0, rule: rule, tokens: Set(ruleTokens)) }

            let standing: TodayLimitState.Standing
            switch rule.kind {
            case .openCountLimit:
                guard let configuration = rule.openCountLimitConfiguration else { return nil }
                let maximum = max(configuration.maximumOpens, 1)
                let used = min(record.openCountUsed, maximum)
                standing = used >= maximum
                    ? .spent
                    : .passes(left: maximum - used, total: maximum)

            case .dailyUsageLimit:
                guard let configuration = rule.dailyUsageLimitConfiguration else { return nil }
                if record.usageLimitReachedAt != nil {
                    standing = .spent
                } else {
                    let budget = TimeInterval(configuration.maximumMinutesPerDay * 60)
                    // Capped at the budget, and deliberately.
                    //
                    // Screen Time starts counting a threshold when the monitoring is
                    // registered, not at midnight -- so a limit set at four in the
                    // afternoon has the evening to run through, whatever the morning
                    // held. This figure is the day's time in those apps, which is the
                    // number every other screen shows, and on the day a rule is created
                    // it can already be past the budget while the block has not fired.
                    // Showing "3 h of 30 min" under an app that still opens would be the
                    // card calling the enforcement broken; the truth about whether it is
                    // spent comes from the extension, in the branch above.
                    let spent = min(matched.reduce(0) { $0 + $1.duration }, budget)
                    standing = .counting(
                        used: LocktyDurationFormatter.abbreviated(spent),
                        total: LocktyDurationFormatter.abbreviated(budget),
                        fraction: budget > 0 ? min(spent / budget, 1) : 0
                    )
                }

            case .sessionDurationLimit:
                guard let configuration = rule.sessionDurationLimitConfiguration else { return nil }
                standing = .perSitting("\(configuration.maximumMinutesPerSession) min at a time")

            case .schedule:
                return nil
            }

            return TodayLimitState(
                id: rule.id,
                name: rule.name,
                standing: standing,
                tokens: tokens,
                apps: appLines(matched, kind: rule.kind)
            )
        }
    }

    /// The rule's apps, largest first, with what each has spent.
    ///
    /// Only the ones that have been used: a list of four apps at "0 min" says nothing
    /// about the day and pushes the rules under it off the screen.
    private static func appLines(
        _ appUsages: [AppUsageState],
        kind: RuleKind
    ) -> [TodayLimitState.AppLine] {
        appUsages
            .filter { kind == .openCountLimit ? $0.opens > 0 : $0.duration >= 60 }
            .sorted { kind == .openCountLimit ? $0.opens > $1.opens : $0.duration > $1.duration }
            .prefix(4)
            .map { usage in
                TodayLimitState.AppLine(
                    id: usage.app.id.rawValue,
                    token: usage.app.applicationToken,
                    name: usage.app.displayName,
                    detail: kind == .openCountLimit
                        ? (usage.opens == 1 ? "1 open" : "\(usage.opens) opens")
                        : LocktyDurationFormatter.abbreviated(usage.duration)
                )
            }
    }

    /// Whether one of the day's apps is one this rule names.
    ///
    /// By token first, and this is the whole reason a daily usage limit read "0 m of 120 m"
    /// all day. The two sides derive their id differently and cannot help it: a rule is
    /// built in the app, where `Application(token:).bundleIdentifier` is nil, so its apps
    /// are stored as `token.<encoded>`; the day's report resolves the same apps through the
    /// installed-applications table and stores them as `com.company.app`. Two ids for one
    /// app, so the sets never intersected and every limit summed nothing.
    ///
    /// The token is the one thing both sides really hold. The id is still checked after it,
    /// for a rule whose app was named some other way and for anything with no token at all.
    ///
    /// A rule covering a whole category still cannot be measured this way -- ManagedSettings
    /// will not say which apps are inside one -- so such a rule shows the time spent on the
    /// apps it does name, which is the honest floor rather than a guess at the rest.
    private static func matches(
        _ usage: AppUsageState,
        rule: Rule,
        tokens: Set<ApplicationToken>
    ) -> Bool {
        if let token = usage.app.applicationToken, tokens.contains(token) { return true }
        return rule.blockedApplications.contains(usage.app.id)
    }
}
