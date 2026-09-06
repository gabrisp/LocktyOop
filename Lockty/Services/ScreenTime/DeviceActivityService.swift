import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

protocol DeviceActivityServicing {
    func schedulePauseRelock(_ allowance: ActivePauseAllowance) async throws
    func scheduleBreakEnd(_ activeBreak: ActiveBreak) async throws
    func syncRoutineSchedules(_ snapshots: [RoutineScheduleSnapshot]) async throws
    func syncRuleSchedules(_ rules: [Rule]) async throws
    /// Drops every allowance monitor, whatever it was counting.
    func cancelPauseRelocks() async
    /// Ends a quick timer on the wall clock, with the app not running.
    func scheduleQuickTimerEnd(routineID: UUID, endsAt: Date) async throws
    func cancelQuickTimer(routineID: UUID) async
    /// Watches the distracting apps so AutoFocus can step in after a long stretch.
    func syncAutoFocus(_ configuration: AutoFocusConfiguration) async throws
    /// Watches a few apps for the moment today passes yesterday in them.
    func syncUsageMilestones(_ milestones: [UsageMilestone]) async throws
}

/// One app, and the minutes today has to pass to be worth saying something about.
nonisolated struct UsageMilestone: Hashable {
    let appID: AppIdentity.ID
    let token: ApplicationToken
    /// Yesterday's minutes in this app. The bar today has to clear.
    let minutes: Int
}

struct LiveDeviceActivityService: DeviceActivityServicing {
    private let center = DeviceActivityCenter()
    private let selectionStore: ScreenTimeSelectionStore

    init(selectionStore: ScreenTimeSelectionStore = ScreenTimeSelectionStore()) {
        self.selectionStore = selectionStore
    }

    /// Name of the usage event that ends an allowance.
    static let pauseAllowanceEvent = DeviceActivityEvent.Name("lockty.pause.allowance")

    /// Name of the usage event that spends a daily-usage rule's budget.
    static let ruleDailyUsageEvent = DeviceActivityEvent.Name("lockty.rule.daily-usage")

    /// Ends the allowance in the background, once the released apps have been used for
    /// as long as it granted.
    ///
    /// This used to be a schedule running from the allowance's start to its end, which
    /// never worked: DeviceActivitySchedule will not take an interval under fifteen
    /// minutes, so every allowance shorter than that -- which is all of them -- threw
    /// and nothing was monitored at all. The app only ever re-locked because opening it
    /// noticed the expiry.
    ///
    /// A usage threshold is monitored instead. The window is long enough for the API to
    /// accept it, and the event fires after the granted minutes have actually been spent
    /// in those apps, which is the case that matters: the phone is in your hand and the
    /// time runs out. Put the phone down and the wall clock expiry still catches it on
    /// the next foreground.
    func schedulePauseRelock(_ allowance: ActivePauseAllowance) async throws {
        let name = DeviceActivityName("lockty.pause.\(allowance.id.uuidString)")
        let tokens = selectionStore.applicationTokens(for: allowance.releasedApplications)
        guard !tokens.isEmpty else { return }

        let minutes = max(1, Int(allowance.expiresAt.timeIntervalSince(allowance.startedAt) / 60))
        let event = DeviceActivityEvent(
            applications: tokens,
            threshold: DateComponents(minute: minutes)
        )

        let calendar = Calendar.current
        // The window *ends* on the allowance's expiry, so intervalDidEnd fires there --
        // on the wall clock, with the app not running. That is the only exact moment
        // this API offers, and it is the one the countdown on screen is showing.
        //
        // The fifteen-minute floor is on the interval's length, not on how soon it ends,
        // so the start is simply put far enough back to clear it. For any allowance
        // shorter than that the start lands earlier today, which means the window is
        // already open and monitoring begins immediately.
        //
        // It used to run a whole day forward from the allowance's start and lean on the
        // usage threshold alone, which fires only once the granted minutes have actually
        // been spent in those apps and is delivered with slack -- so the countdown hit
        // 0:00 and everything stayed unlocked until the system got round to it.
        let end = calendar.dateComponents([.hour, .minute, .second], from: allowance.expiresAt)
        let start = calendar.dateComponents(
            [.hour, .minute, .second],
            from: allowance.expiresAt.addingTimeInterval(-16 * 60)
        )

        try center.startMonitoring(
            name,
            during: DeviceActivitySchedule(intervalStart: start, intervalEnd: end, repeats: false),
            events: [Self.pauseAllowanceEvent: event]
        )
    }

    /// Ending a routine ends the allowances it granted, and a monitor left counting
    /// against a routine that is over reaches its threshold later and re-applies a shield
    /// for something nobody is running any more.
    func cancelPauseRelocks() async {
        let pauseActivities = center.activities.filter { $0.rawValue.hasPrefix("lockty.pause.") }
        guard !pauseActivities.isEmpty else { return }
        center.stopMonitoring(pauseActivities)
    }

    /// A quick timer's end, on the clock.
    ///
    /// The same trick the allowance window uses, for the same reason: the fifteen-minute
    /// floor is on the interval's *length*, not on how soon it ends, so the start is put
    /// far enough back to clear it and `intervalDidEnd` still lands on the minute the
    /// countdown is showing. A ten-minute timer therefore opens a window that began six
    /// minutes ago, which is fine -- nothing happens at the start of it.
    func scheduleQuickTimerEnd(routineID: UUID, endsAt: Date) async throws {
        let name = DeviceActivityName("lockty.quick.\(routineID.uuidString)")
        let calendar = Calendar.current
        let end = calendar.dateComponents([.hour, .minute, .second], from: endsAt)
        let start = calendar.dateComponents(
            [.hour, .minute, .second],
            from: endsAt.addingTimeInterval(-16 * 60)
        )

        try center.startMonitoring(
            name,
            during: DeviceActivitySchedule(intervalStart: start, intervalEnd: end, repeats: false)
        )
    }

    func cancelQuickTimer(routineID: UUID) async {
        center.stopMonitoring([DeviceActivityName("lockty.quick.\(routineID.uuidString)")])
    }

    /// Registers the usage threshold AutoFocus intervenes on.
    ///
    /// A whole-day window with a usage event inside it, which is the only shape Screen
    /// Time offers for "tell me once they have spent this long in these apps". The event
    /// fires once per window; the monitor re-registers it afterwards, which is what makes
    /// the cooldown between interventions a real thing rather than a stored number.
    func syncAutoFocus(_ configuration: AutoFocusConfiguration) async throws {
        let tokens = selectionStore.applicationTokens(for: configuration.distractingApplicationIDs)
        guard !tokens.isEmpty else {
            center.stopMonitoring([DeviceActivityName(AutoFocusIntervention.activityName)])
            print("AutoFocus not monitored: no distracting apps selected")
            return
        }

        let milestones = DistractionMilestones.milestones(for: configuration.interventionLevel)
        guard !milestones.isEmpty else { return }

        // One event per milestone, all inside the same day-long window. A usage event
        // fires once per interval, so registering six of them is six notices at six
        // different points of the day and never the same one twice -- where a single
        // threshold could only ever say one thing, at whichever number was in the menu.
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        for milestone in milestones {
            events[DeviceActivityEvent.Name(milestone.eventName)] = DeviceActivityEvent(
                applications: tokens,
                threshold: DateComponents(minute: milestone.minutes)
            )
        }

        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )

        var selection = FamilyActivitySelection()
        selection.applicationTokens = tokens

        // Untouched when nothing about it has changed: a restart puts the counted minutes
        // back to zero, and the time spent in a distracting app is exactly what this is
        // counting. The day is in the fingerprint so tomorrow re-registers on its own.
        reconcile(
            prefix: AutoFocusIntervention.activityName,
            planned: [
                AutoFocusIntervention.activityName: PlannedMonitor(
                    name: DeviceActivityName(AutoFocusIntervention.activityName),
                    schedule: schedule,
                    events: events,
                    fingerprint: Self.fingerprint(
                        of: selection,
                        plus: "autofocus-\(configuration.interventionLevel.rawValue)-\(RuleEnforcementState.dayKey())"
                    )
                )
            ]
        )
        print("AutoFocus monitoring \(tokens.count) app(s) at \(milestones.map(\.minutes)) minutes")
    }

    /// Registers the "you have passed yesterday" watches.
    ///
    /// A notification worth sending is one that could not have been sent an hour earlier.
    /// "You used your phone less than yesterday" at eight in the morning is not a
    /// finding, it is arithmetic about a day that has not happened -- but "you have
    /// already spent longer in TikTok than you did all of yesterday" is true the moment
    /// it is true, whatever the clock says.
    ///
    /// So it is a usage threshold set to yesterday's figure. iOS counts the minutes and
    /// launches the monitor extension the moment they are passed; nothing has to be
    /// awake, and nothing has to guess.
    func syncUsageMilestones(_ milestones: [UsageMilestone]) async throws {
        var planned: [String: PlannedMonitor] = [:]

        for milestone in milestones where milestone.minutes > 0 {
            var selection = FamilyActivitySelection()
            selection.applicationTokens = [milestone.token]

            let event = DeviceActivityEvent(
                applications: [milestone.token],
                threshold: DateComponents(minute: milestone.minutes)
            )

            // The whole day, repeating, like every other daily threshold. The day is in
            // the fingerprint below, so tomorrow's figure replaces today's.
            let schedule = DeviceActivitySchedule(
                intervalStart: DateComponents(hour: 0, minute: 0),
                intervalEnd: DateComponents(hour: 23, minute: 59),
                repeats: true
            )

            let name = "\(UsageMilestoneNotice.activityPrefix)\(milestone.appID.rawValue)"
            planned[name] = PlannedMonitor(
                name: DeviceActivityName(name),
                schedule: schedule,
                events: [DeviceActivityEvent.Name(UsageMilestoneNotice.eventName): event],
                fingerprint: Self.fingerprint(
                    of: selection,
                    plus: "milestone-\(milestone.minutes)-\(RuleEnforcementState.dayKey())"
                )
            )
        }

        reconcile(prefix: UsageMilestoneNotice.activityPrefix, planned: planned)
    }

    func scheduleBreakEnd(_ activeBreak: ActiveBreak) async throws {
        let name = DeviceActivityName("lockty.break.\(activeBreak.id.uuidString)")
        let calendar = Calendar.current
        let start = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: activeBreak.startedAt)
        let end = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: activeBreak.endsAt)
        try center.startMonitoring(name, during: DeviceActivitySchedule(intervalStart: start, intervalEnd: end, repeats: false))
    }

    /// Registers the daily budget of every `.dailyUsageLimit` rule.
    ///
    /// This is the one limit Screen Time can measure for us: a usage threshold over the
    /// rule's apps, inside a window that spans the day and repeats. When the threshold is
    /// reached the extension marks the rule as spent and the shield goes up; the next
    /// day's `intervalDidStart` clears it again.
    ///
    /// The other two kinds are deliberately absent. There is no "times opened" event, and
    /// a threshold measures a whole interval rather than one sitting, so an open count and
    /// a per-session cap cannot be observed here at all -- they are enforced at the
    /// shield instead, which sees every trip through it.
    ///
    /// Only what has actually changed is re-registered. This used to stop every rule
    /// monitor and start them all again on each call, and restarting a monitor restarts
    /// its interval -- which throws away the minutes counted towards the threshold. The
    /// call happens on launch and on every visit to the rules list, so a daily budget was
    /// reset to zero several times a day and a limit of an hour was quite unreachable.
    func syncRuleSchedules(_ rules: [Rule]) async throws {
        var planned: [String: PlannedMonitor] = [:]

        for rule in rules where rule.isEnabled && rule.kind == .dailyUsageLimit {
            guard let configuration = rule.dailyUsageLimitConfiguration,
                  configuration.maximumMinutesPerDay > 0
            else { continue }

            let selection = selectionStore.mergedSelection(scopes: rule.selectionScopes)
            guard !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty else {
                continue
            }

            // Counting the whole day, not the part of it since we asked.
            //
            // A threshold is measured from the moment monitoring is registered, so a
            // thirty-minute limit set at four in the afternoon gave the evening thirty
            // fresh minutes however much of the day had already gone into that app -- the
            // rule simply did not fire on the day it was made. `includesPastActivity`
            // tells Screen Time to count the minutes already spent in the interval, which
            // is what "30 minutes a day" says.
            let event = DeviceActivityEvent(
                applications: selection.applicationTokens,
                categories: selection.categoryTokens,
                threshold: DateComponents(minute: configuration.maximumMinutesPerDay),
                includesPastActivity: true
            )

            // 00:00 to 23:59, repeating: the widest window the API takes, which is what
            // "per day" means. The budget resets when the interval does.
            let schedule = DeviceActivitySchedule(
                intervalStart: DateComponents(hour: 0, minute: 0),
                intervalEnd: DateComponents(hour: 23, minute: 59),
                repeats: true
            )

            let name = "lockty.rule.\(rule.id.uuidString)"
            planned[name] = PlannedMonitor(
                name: DeviceActivityName(name),
                schedule: schedule,
                events: [Self.ruleDailyUsageEvent: event],
                fingerprint: Self.fingerprint(
                    of: selection,
                    // "past" is part of it: the monitors registered before this counted
                    // from registration, and without a changed fingerprint the ledger
                    // would consider them current and never replace them.
                    plus: "usage-\(configuration.maximumMinutesPerDay)-past"
                )
            )
        }

        reconcile(prefix: "lockty.rule.", planned: planned)
    }

    /// Registers a repeating daily window per scheduled routine so the monitor
    /// extension can start/stop it with the app not running. Existing routine
    /// monitoring is torn down first so removed or edited schedules don't linger.
    func syncRoutineSchedules(_ snapshots: [RoutineScheduleSnapshot]) async throws {
        let stale = center.activities.filter { $0.rawValue.hasPrefix("lockty.routine.") }
        if !stale.isEmpty {
            center.stopMonitoring(stale)
        }

        for snapshot in snapshots where !snapshot.schedule.weekdays.isEmpty {
            let name = DeviceActivityName("lockty.routine.\(snapshot.id.uuidString)")
            // DeviceActivity has no weekday filter, so this monitors the daily window
            // and the extension checks the weekday when the interval starts.
            let schedule = DeviceActivitySchedule(
                intervalStart: DateComponents(
                    hour: snapshot.schedule.hour,
                    minute: snapshot.schedule.minute
                ),
                intervalEnd: DateComponents(
                    hour: snapshot.schedule.endHour,
                    minute: snapshot.schedule.endMinute
                ),
                repeats: true
            )

            do {
                try center.startMonitoring(name, during: schedule)
            } catch {
                print("Routine schedule monitoring failed for \(snapshot.name): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Registering only what changed

    /// One activity as it should be registered.
    private struct PlannedMonitor {
        let name: DeviceActivityName
        let schedule: DeviceActivitySchedule
        let events: [DeviceActivityEvent.Name: DeviceActivityEvent]
        /// What this monitor is watching and for how long, as a value that changes only
        /// when one of those does.
        let fingerprint: String
    }

    /// Brings the monitors under a prefix in line with what they should be, touching as
    /// few of them as possible.
    ///
    /// The point of the ledger is that DeviceActivityCenter will tell you which
    /// activities are running but not what they were registered with, so there is no way
    /// to ask whether the one already running is the one you want. Recording the
    /// fingerprint alongside is what makes "leave it alone" possible -- and leaving it
    /// alone is the whole job, because a monitor's counted usage lives and dies with its
    /// registration.
    private func reconcile(prefix: String, planned: [String: PlannedMonitor]) {
        var ledger = Self.loadLedger()
        let running = Set(center.activities.map(\.rawValue))

        let obsolete = running.filter { name in
            guard name.hasPrefix(prefix) else { return false }
            guard let plan = planned[name] else { return true }
            return ledger[name] != plan.fingerprint
        }
        if !obsolete.isEmpty {
            center.stopMonitoring(obsolete.map(DeviceActivityName.init(rawValue:)))
            for name in obsolete { ledger[name] = nil }
        }

        for (name, plan) in planned where ledger[name] == nil || !running.contains(name) {
            do {
                try center.startMonitoring(plan.name, during: plan.schedule, events: plan.events)
                ledger[name] = plan.fingerprint
            } catch {
                ledger[name] = nil
                print("Monitoring failed for \(name): \(error.localizedDescription)")
            }
        }

        // Anything left in the ledger under this prefix that is no longer wanted has
        // already been stopped above; this drops the record of it.
        ledger = ledger.filter { !$0.key.hasPrefix(prefix) || planned[$0.key] != nil }
        Self.saveLedger(ledger)
    }

    /// The fingerprint of a selection and the threshold it is measured against.
    ///
    /// Built from the encoded tokens rather than from their hash values: Swift's hashing
    /// is seeded per process, so a hash would differ on every launch and every monitor
    /// would look changed -- which is the bug this exists to avoid.
    private static func fingerprint(of selection: FamilyActivitySelection, plus suffix: String) -> String {
        let data = (try? JSONEncoder().encode(selection)) ?? Data()
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        return "\(String(hash, radix: 16)).\(suffix)"
    }

    private static let ledgerKey = "lockty.device-activity.registrations"

    private static func loadLedger() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: ledgerKey) as? [String: String] ?? [:]
    }

    private static func saveLedger(_ ledger: [String: String]) {
        UserDefaults.standard.set(ledger, forKey: ledgerKey)
    }
}
