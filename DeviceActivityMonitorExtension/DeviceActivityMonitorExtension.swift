import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import UserNotifications

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        // Scheduled routines start here, with the app not running.
        RuntimeRepairCoordinator().startScheduledRoutineIfNeeded(for: activity)
        // And a daily-usage rule's budget is handed back here: this is the new day.
        RuntimeRepairCoordinator().resetRuleBudgetIfNeeded(for: activity)
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        RuntimeRepairCoordinator().repair(afterEnding: activity)
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)

        if let milestone = DistractionMilestones.milestone(forEvent: event.rawValue) {
            RuntimeRepairCoordinator().deliverDistractionMilestone(milestone)
            return
        }

        if event.rawValue == UsageMilestoneNotice.eventName {
            RuntimeRepairCoordinator().deliverUsageMilestone(for: activity)
            return
        }

        RuntimeRepairCoordinator().repair(afterThresholdFor: activity, event: event)
    }
}

private struct RuntimeRepairCoordinator {
    private let store = AppGroupStore()
    private let selectionStore = ScreenTimeSelectionStore()
    private let resolver = ShieldPolicyResolver()
    private let managedSettingsStore = ManagedSettingsStore(named: ManagedSettingsStore.Name("lockty"))

    func repair(afterEnding activity: DeviceActivityName) {
        if activity.rawValue.hasPrefix("lockty.routine.") {
            endScheduledRoutine(activityName: activity.rawValue)
            return
        }

        // A quick timer running out. It is not in the routine library -- it was made on
        // the spot and exists only in the runtime state -- so it is ended by id here
        // rather than by looking a snapshot up.
        if activity.rawValue.hasPrefix("lockty.quick."),
           let id = UUID(uuidString: String(activity.rawValue.dropFirst("lockty.quick.".count))) {
            endQuickTimer(routineID: id)
            return
        }

        // An allowance's window is scheduled to end on its expiry, so this is the moment
        // it runs out -- not a moment to go and check whether it has. Asking isExpired
        // here missed the ones the system delivered a second early, and then nothing
        // relocked until something else noticed.
        if activity.rawValue.hasPrefix("lockty.pause.") {
            try? store.updateRuntimeState { state in
                state.activePauseAllowance = nil
                state.pendingPause = nil
            }
            PauseAllowanceLiveActivityTermination.endAllBlocking()
        }

        repairRuntimeState(activityName: activity.rawValue)
    }

    /// Ends a quick timer and recomputes the shield without it.
    ///
    /// The same shape as a scheduled routine ending: drop it from `activeRoutines`, drop
    /// any break it granted, and let the resolver work out what is left blocked -- which
    /// is what keeps a second routine's apps shut when this one stops.
    func endQuickTimer(routineID: UUID) {
        try? store.updateRuntimeState { state in
            state.activeRoutines.removeAll { $0.routineID == routineID }
            state.activeBreaks.removeAll { $0.routineID == routineID }
        }
        repairRuntimeState(activityName: "lockty.quick.\(routineID.uuidString)")
    }

    /// The schedule is a plain daily window (DeviceActivity has no weekday filter), so
    /// the configured weekdays are checked here before anything is applied.
    func startScheduledRoutineIfNeeded(for activity: DeviceActivityName) {
        guard activity.rawValue.hasPrefix("lockty.routine."),
              let id = UUID(uuidString: String(activity.rawValue.dropFirst("lockty.routine.".count))),
              let snapshot = store.loadRoutineScheduleSnapshots().first(where: { $0.id == id })
        else { return }

        let weekday = Weekday(rawValue: Calendar.current.component(.weekday, from: Date()))
        guard let weekday, snapshot.schedule.weekdays.contains(weekday) else {
            print("Scheduled routine \(snapshot.name) skipped: not scheduled for today")
            return
        }

        // A routine on hold does not start. Checked here rather than by tearing down its
        // monitoring, so the hold can run out on its own and the routine simply begins
        // again at its next window -- with nothing to remember to re-register.
        guard !store.loadRulePauseState().isPaused(id) else {
            print("Scheduled routine \(snapshot.name) skipped: paused")
            return
        }

        // Read and written in one step held by the store, rather than a copy loaded here
        // and saved back afterwards. Two processes write this file, and a whole-state save
        // puts back everything the copy was holding -- including routines the app has
        // ended in the meantime, which then reappear on the next foreground because
        // `restore(from:)` takes the App Group at its word.
        var didStart = false
        try? store.updateRuntimeState { runtimeState in
            // Alongside whatever else is running, not instead of it. This used to bail out
            // whenever anything was active, so a routine whose window overlapped another's
            // was dropped at its start and never reconsidered -- it lost its entire window
            // without a word. Only starting the same routine twice is refused.
            guard !runtimeState.activeRoutines.contains(where: { $0.routineID == id }) else { return }

            runtimeState.activeRoutines.append(snapshot.makeActiveRoutine(startedAt: Date()))
            didStart = true
        }
        guard didStart else { return }
        print("Started scheduled routine \(snapshot.name) from the monitor extension")
        repairRuntimeState(activityName: activity.rawValue)
    }

    /// A new day for a daily-usage rule: the interval it was budgeted against has just
    /// restarted, so whatever it spent yesterday stops shielding anything.
    ///
    /// Only a record from another day is cleared. An interval start is not proof of a new
    /// day -- registering a monitor on a window that is already open delivers one
    /// immediately -- and this used to drop the record whichever day it belonged to, so
    /// every re-registration handed the rule its whole budget back. That is what made a
    /// daily limit vanish on opening Lockty: the app re-registered its monitors on
    /// launch, the system called this, and the minutes already spent were forgotten.
    ///
    /// Clearing it is still worth doing at a real rollover, because the shield has to
    /// come down here and now -- but the recompute below is what actually lifts it, and
    /// a record left over from yesterday already reads as a fresh one.
    func resetRuleBudgetIfNeeded(for activity: DeviceActivityName) {
        guard let ruleID = Self.ruleID(from: activity) else { return }

        let today = RuleEnforcementState.dayKey()
        var didReset = false
        try? store.updateRuleEnforcementState { state in
            guard let record = state.records[ruleID], record.dayKey != today else { return }
            state.records[ruleID] = nil
            didReset = true
        }

        if didReset {
            print("Rule \(ruleID.uuidString) budget reset for a new day")
        }
        repairRuntimeState(activityName: activity.rawValue)
    }

    private static func ruleID(from activity: DeviceActivityName) -> UUID? {
        let prefix = "lockty.rule."
        guard activity.rawValue.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(activity.rawValue.dropFirst(prefix.count)))
    }

    /// Ends one scheduled routine, leaving any others running.
    ///
    /// Only this routine and its own break are removed. The shield is then recomputed
    /// from what is left, which is what frees exactly the apps this routine was holding:
    /// one that another running routine also blocks stays blocked, because that routine
    /// is still in the union.
    private func endScheduledRoutine(activityName: String) {
        guard let id = UUID(uuidString: String(activityName.dropFirst("lockty.routine.".count))) else {
            return
        }

        var endedLiveActivities = false
        var didEnd = false
        try? store.updateRuntimeState { runtimeState in
            guard let active = runtimeState.activeRoutines.first(where: { $0.routineID == id }) else {
                return
            }

            // Only a session this window actually started. A routine's monitoring window is
            // registered for its schedule and ends at the schedule's end whatever is
            // happening -- so starting the same routine by hand outside its hours got it
            // switched off at the end of a window it had nothing to do with, and the block
            // simply lifted. The trigger records how the session began, and a manual one ends
            // when a person says so.
            guard case .schedule = active.trigger else { return }

            runtimeState.activeRoutines.removeAll { $0.routineID == id }
            runtimeState.activeBreaks.removeAll { $0.routineID == id }

            // The allowance and the request the shield was waiting on belong to the session
            // as a whole, so they only go once there is no session left to belong to.
            if runtimeState.activeRoutines.isEmpty {
                runtimeState.activePauseAllowance = nil
                runtimeState.pendingPause = nil
                endedLiveActivities = true
            }
            didEnd = true
        }

        guard didEnd else {
            print("Ignoring schedule end for routine \(id.uuidString): not running, or started by hand")
            return
        }
        if endedLiveActivities { PauseAllowanceLiveActivityTermination.endAllBlocking() }
        repairRuntimeState(activityName: activityName)
    }

    /// The allowance's usage threshold has been reached: the granted minutes have been
    /// spent, so it ends now whether or not its wall clock has run out.
    /// The intervention stepping in.
    ///
    /// Nothing has to wake the app for this. iOS itself counts the time spent in the
    /// chosen apps against the threshold and launches *this extension* when it is
    /// crossed -- a separate process, with the app closed, possibly for days. All the app
    /// ever does is register the threshold.
    ///
    /// Says something rather than shielding, which is not a preference: a screen in front
    /// of an app is only allowed against a block the person set up, and this one is
    /// noticed rather than chosen.
    func deliverDistractionMilestone(_ milestone: DistractionMilestones.Milestone) {
        let configuration = store.loadAutoFocusConfiguration()
        guard configuration.notificationsEnabled else {
            print("Distraction milestone \(milestone.minutes)m reached but notifications are off")
            return
        }

        // Built here rather than baked into the milestone: which app took the time, how
        // today stands against yesterday and what share of the screen this is are facts
        // that only exist at the moment of delivery. A notice that says "34 min, most of
        // it Instagram" answers the question the bare figure only raises.
        let line = DistractionMilestones.line(
            for: milestone,
            context: distractionContext(store: store)
        )

        let content = UNMutableNotificationContent()
        content.title = line.title
        content.body = line.body
        content.sound = .default

        // Immediately, with no trigger: the moment it fires *is* the moment. And keyed by
        // the milestone and the day, so a threshold that somehow reports twice replaces
        // its own notification rather than stacking a second copy of it.
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: "distraction-\(milestone.minutes)-\(RuleEnforcementState.dayKey())",
                content: content,
                trigger: nil
            )
        )

        print("Distraction milestone delivered at \(milestone.minutes)m")
    }

    /// What the report snapshots can tell a distraction notice right now.
    ///
    /// Every part is optional and every part is allowed to be missing: Screen Time
    /// delivers these late, and a notice claiming "0 min in Instagram" over an app you
    /// have been in all morning is worse than one that does not mention it.
    private func distractionContext(store: AppGroupStore) -> DistractionMilestones.Context {
        var context = DistractionMilestones.Context()
        let distracting = store.loadAutoFocusConfiguration().distractingApplicationIDs
        let catalog = store.loadAppNameCatalog()

        if let today = try? store.loadScreenTimeReportSnapshot(for: DayKey(date: Date())) {
            context.todayTotalMinutes = Int(today.totalActivityDuration / 60)

            if let top = today.applications
                .filter({ distracting.contains($0.app.id) })
                .max(by: { $0.totalActivityDuration < $1.totalActivityDuration }) {
                // The catalogue first: from an extension, a token's own
                // `localizedDisplayName` is nil, which is the whole reason it exists.
                context.topAppName = catalog.record(for: top.app.id)?.displayName ?? top.app.displayName
                context.topAppMinutes = Int(top.totalActivityDuration / 60)
                context.topAppPickups = top.pickups
            }
        }

        let calendar = Calendar.current
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()),
           let snapshot = try? store.loadScreenTimeReportSnapshot(for: DayKey(date: yesterday)) {
            let total = snapshot.applications
                .filter { distracting.contains($0.app.id) }
                .reduce(0) { $0 + $1.totalActivityDuration }
            if total > 0 { context.yesterdayMinutes = Int(total / 60) }
        }

        return context
    }

    /// Today has passed yesterday in one app.
    ///
    /// The name comes out of the catalogue the report extension keeps, because here --
    /// in an extension, from a token -- `Application(token:).localizedDisplayName` is
    /// nil. That is the whole reason the catalogue exists: without it this notification
    /// would have to say "an app", which is a notification about nothing.
    func deliverUsageMilestone(for activity: DeviceActivityName) {
        guard let appID = UsageMilestoneNotice.appID(from: activity.rawValue) else { return }

        let catalog = store.loadAppNameCatalog()
        guard let record = catalog.record(for: appID) else {
            print("Usage milestone for \(appID.rawValue) skipped: no name on file")
            return
        }

        // Yesterday's figure, read back rather than carried in the activity name: the
        // name has to stay the same across the day or the monitor would be re-registered
        // every time the figure was recomputed.
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let minutes = (try? store.loadScreenTimeReportSnapshot(for: DayKey(date: yesterday)))?
            .applications
            .first { $0.app.id == appID }?
            .totalActivityDuration ?? 0

        guard minutes > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = UsageMilestoneNotice.title
        content.body = UsageMilestoneNotice.message(
            appName: record.displayName,
            yesterday: Self.durationText(minutes)
        )
        content.sound = .default

        UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: "milestone-\(appID.rawValue)-\(RuleEnforcementState.dayKey())",
                content: content,
                trigger: nil
            )
        )
        print("Usage milestone delivered for \(record.displayName)")
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours) h" : "\(hours) h \(remainder) min"
    }

    // The re-arm that used to live here is gone with the single threshold it existed
    // for. There is nothing to re-arm now: each milestone is its own event with its own
    // figure, every one fires once per day by construction, and the cooldown between
    // them is simply the time it takes to spend the next fifteen minutes.

    func repair(afterThresholdFor activity: DeviceActivityName, event: DeviceActivityEvent.Name) {
        _ = event
        // A daily-usage rule has spent the minutes it was given. Marking it here is what
        // puts its apps behind the shield, since repairRuntimeState below recomputes the
        // policy from exactly this record.
        if let ruleID = Self.ruleID(from: activity) {
            try? store.updateRuleEnforcementState { state in
                state.update(ruleID) { record in
                    record.usageLimitReachedAt = Date()
                }
            }

            // And into the history, because this is the one thing about a limit that must
            // outlive the day: the enforcement record is cleared at midnight, and a day
            // the app is never opened would otherwise leave no trace that the rule fired.
            // Only the flag -- the extension has no report to read, and writing figures it
            // does not have would overwrite what the app wrote with zeroes.
            try? store.updateRuleHistory { history in
                history.markReached(ruleID)
            }

            print("Rule \(ruleID.uuidString) reached its daily usage limit")
        }

        if activity.rawValue.hasPrefix("lockty.pause.") {
            try? store.updateRuntimeState { state in
                state.activePauseAllowance = nil
                state.pendingPause = nil
            }
            // The countdown on the Lock Screen is the allowance. Reaching the threshold
            // is the allowance ending, so the activity has to end with it -- it used to
            // be left running against an allowance that no longer existed, still ticking
            // down over apps this call has already re-shielded.
            PauseAllowanceLiveActivityTermination.endAllBlocking()
        }
        repairRuntimeState(activityName: activity.rawValue)
    }

    private func repairRuntimeState(activityName: String) {
        // Everything that does not depend on the runtime state is read first, so the
        // read-modify-write below is as short as it can be.
        //
        // This used to load a copy at the top, read every pause rule and shield rule,
        // resolve the whole policy, and only then save the copy back -- putting back
        // whatever it had been holding all that while. Anything the app wrote inside that
        // window was undone, and since this runs on *every* monitor callback, a routine
        // ended in the app came back silently on the next foreground: `restore(from:)`
        // takes the App Group at its word.
        let pauseRules = storedPauseRules()
        let shieldRules = store.loadShieldRules()
        let alwaysAllowed = store.loadAlwaysAllowedApplications()

        var endedLiveActivities = false
        var resolvedPolicy: ShieldPolicy?

        try? store.updateRuntimeState { runtimeState in
        if activityName.hasPrefix("lockty.pause."),
           runtimeState.activePauseAllowance?.isExpired == true {
            runtimeState.activePauseAllowance = nil
            runtimeState.pendingPause = nil
            endedLiveActivities = true
        }

        if activityName.hasPrefix("lockty.break.") {
            // Each expired break is dropped on its own. They belong to different
            // routines, and clearing them wholesale would put back the blocks of a
            // routine whose break is still running.
            for expired in runtimeState.activeBreaks.filter({ $0.endsAt <= Date() }) {
                runtimeState.activeBreaks.removeAll { $0.id == expired.id }
                print("Break monitor expired breakID=\(expired.id.uuidString) restoring routine \(expired.routineID.uuidString) shields")
            }
        }

        let effectivePolicy = resolver.resolve(
            activeRoutines: runtimeState.activeRoutines,
            activeBreaks: runtimeState.activeBreaks,
            activePauseAllowance: runtimeState.livePauseAllowance,
            pauseRules: pauseRules,
            rules: shieldRules.rules,
            ruleEnforcement: shieldRules.enforcement,
            alwaysAllowedApplications: alwaysAllowed
        )

        runtimeState.shieldPolicy = effectivePolicy
        runtimeState.recoveryFlags = []
        resolvedPolicy = effectivePolicy
        }

        if endedLiveActivities { PauseAllowanceLiveActivityTermination.endAllBlocking() }
        guard let resolvedPolicy else { return }
        apply(policy: resolvedPolicy)
    }

    /// The pause rules as the resolver wants them.
    private func storedPauseRules() -> [PauseRule] {
        store.loadPauseRuleSnapshots()
            .filter(\.isEnabled)
            .map {
                PauseRule(
                    id: $0.id,
                    application: $0.application,
                    isEnabled: $0.isEnabled,
                    steps: $0.steps,
                    allowanceDuration: $0.allowanceDuration,
                    relockAfterAllowance: $0.relockAfterAllowance,
                    createdAt: $0.updatedAt,
                    updatedAt: $0.updatedAt
                )
            }
    }

    private func apply(policy: ShieldPolicy) {
        var selection = (try? selectionStore.selection(for: policy)) ?? FamilyActivitySelection()
        let blockedDomains = Set(policy.blockedDomains.map(ManagedSettings.WebDomain.init(domain:)))

        // Same exemption the app applies: an app released by a live pause allowance must
        // not be re-shielded here, whether it is blocked by token or by category.
        let exemptTokens = selectionStore.applicationTokens(for: policy.exemptApplications)
        selection.applicationTokens.subtract(exemptTokens)

        print(
            """
            Monitor extension applying policy reason=\(String(describing: policy.reason)) \
            apps=\(selection.applicationTokens.count) \
            categories=\(selection.categoryTokens.count) \
            domains=\(selection.webDomainTokens.count) \
            manualDomains=\(blockedDomains.count) \
            exempt=\(exemptTokens.count)
            """
        )

        managedSettingsStore.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        managedSettingsStore.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        managedSettingsStore.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens, except: exemptTokens)
        // `.specific` is an *allow* list. This said "let the routine's blocked sites
        // through and nothing else", which shut off the entire web whenever the
        // extension applied a policy with a domain in it -- the same inversion the app
        // had, fixed there and left here, so it survived in exactly the path that runs
        // with the app closed.
        managedSettingsStore.webContent.blockedByFilter = webContentFilter(
            blocking: blockedDomains,
            restrictions: policy.contentRestrictions,
            guards: policy.strictGuards
        )

        // The device-level switches, which this path was not applying at all. A routine
        // that started on its schedule, or any background repair, silently dropped the
        // adult filter, the purchase block, the install block and every one of Strict
        // Mode's doors -- the app applied them and the extension quietly did not, so the
        // same routine enforced less depending on who had put its shield up.
        let restrictions = policy.contentRestrictions
        let guards = policy.strictGuards
        managedSettingsStore.appStore.denyInAppPurchases = restrictions.blocksITunesPurchases ? true : nil
        managedSettingsStore.appStore.requirePasswordForPurchases = restrictions.blocksITunesPurchases ? true : nil
        managedSettingsStore.application.denyAppInstallation = restrictions.blocksAppInstallation ? true : nil
        managedSettingsStore.application.denyAppRemoval = guards.preventsAppRemoval ? true : nil
        managedSettingsStore.dateAndTime.requireAutomaticDateAndTime = guards.preventsDateAndTimeChanges ? true : nil
        managedSettingsStore.passcode.lockPasscode = guards.preventsPasscodeChanges ? true : nil
    }

    /// The web filter for a policy, or nil when it wants nothing filtered.
    ///
    /// `.auto` carries both jobs: its argument is the set of sites to block, and turning
    /// it on at all is what enables the automatic adult-content filter.
    private func webContentFilter(
        blocking domains: Set<ManagedSettings.WebDomain>,
        restrictions: ContentRestrictions,
        guards: StrictModeGuards
    ) -> ManagedSettings.WebContentSettings.FilterPolicy? {
        guard !domains.isEmpty || restrictions.blocksAdultWebContent else { return nil }
        return .auto(domains)
    }

    func markShieldRestoreNeeded() {
        try? store.updateRuntimeState { state in
            state.recoveryFlags.insert(.shieldRestoreNeeded)
        }
    }

    func markExpiredRuntimeNeedsRepair() {
        try? store.updateRuntimeState { state in
            state.recoveryFlags.insert(.expiredPauseNeedsRelock)
            state.recoveryFlags.insert(.expiredBreakNeedsFinalization)
        }
    }
}
