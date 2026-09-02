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
        let name = DeviceActivityName(AutoFocusIntervention.activityName)
        center.stopMonitoring([name])

        let tokens = selectionStore.applicationTokens(for: configuration.distractingApplicationIDs)
        guard !tokens.isEmpty else {
            print("AutoFocus not monitored: no distracting apps selected")
            return
        }

        let minutes = AutoFocusIntervention.thresholdMinutes(for: configuration.interventionLevel)
        let event = DeviceActivityEvent(
            applications: tokens,
            threshold: DateComponents(minute: minutes)
        )

        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )

        try center.startMonitoring(
            name,
            during: schedule,
            events: [DeviceActivityEvent.Name(AutoFocusIntervention.eventName): event]
        )
        print("AutoFocus monitoring \(tokens.count) app(s) at \(minutes)m")
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
    func syncRuleSchedules(_ rules: [Rule]) async throws {
        let stale = center.activities.filter { $0.rawValue.hasPrefix("lockty.rule.") }
        if !stale.isEmpty {
            center.stopMonitoring(stale)
        }

        for rule in rules where rule.isEnabled && rule.kind == .dailyUsageLimit {
            guard let configuration = rule.dailyUsageLimitConfiguration,
                  configuration.maximumMinutesPerDay > 0
            else { continue }

            let selection = selectionStore.mergedSelection(scopes: rule.selectionScopes)
            guard !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty else {
                continue
            }

            let event = DeviceActivityEvent(
                applications: selection.applicationTokens,
                categories: selection.categoryTokens,
                threshold: DateComponents(minute: configuration.maximumMinutesPerDay)
            )

            // 00:00 to 23:59, repeating: the widest window the API takes, which is what
            // "per day" means. The budget resets when the interval does.
            let schedule = DeviceActivitySchedule(
                intervalStart: DateComponents(hour: 0, minute: 0),
                intervalEnd: DateComponents(hour: 23, minute: 59),
                repeats: true
            )

            do {
                try center.startMonitoring(
                    DeviceActivityName("lockty.rule.\(rule.id.uuidString)"),
                    during: schedule,
                    events: [Self.ruleDailyUsageEvent: event]
                )
            } catch {
                print("Rule usage monitoring failed for \(rule.name): \(error.localizedDescription)")
            }
        }
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
}
