import Foundation

/// Keeps the DeviceActivity monitoring and the App Group snapshots in step with the
/// stored routines, so a scheduled routine can start with the app not running.
///
/// The monitor extension can't reach Core Data, so every scheduled routine is mirrored
/// into the App Group as a RoutineScheduleSnapshot whenever routines change.
@MainActor
struct RoutineScheduleCoordinator {
    private let repository: RoutineRepository
    private let routineExecutionRepository: RoutineExecutionRepository
    private let appGroupStore: AppGroupStore
    private let deviceActivityService: DeviceActivityServicing
    private let alarmService: AlarmServicing

    init(
        repository: RoutineRepository,
        routineExecutionRepository: RoutineExecutionRepository,
        appGroupStore: AppGroupStore,
        deviceActivityService: DeviceActivityServicing,
        alarmService: AlarmServicing
    ) {
        self.repository = repository
        self.routineExecutionRepository = routineExecutionRepository
        self.appGroupStore = appGroupStore
        self.deviceActivityService = deviceActivityService
        self.alarmService = alarmService
    }

    /// Registers the daily budget of every usage-limited rule, and drops the counters of
    /// rules that are gone.
    ///
    /// Separate from the routine sync above only because the two read different stores;
    /// `sync()` calls both, so nothing has to remember to call this one on its own.
    func syncRules() async {
        let rules = appGroupStore.loadStoredRules()

        var enforcement = appGroupStore.loadRuleEnforcementState()
        enforcement.prune(keeping: Set(rules.map(\.id)))
        try? appGroupStore.saveRuleEnforcementState(enforcement)

        do {
            try await deviceActivityService.syncRuleSchedules(rules)
            print("Synced \(rules.count) rule(s) for background enforcement")
        } catch {
            print("Rule schedule sync failed: \(error.localizedDescription)")
        }
    }

    /// When the last full sync ran.
    ///
    /// The lists call this on every appearance, and a sync reads every rule and routine,
    /// fingerprints each monitor and asks DeviceActivity what it is running. Nothing of
    /// that changes twice in a few seconds, and it was the slowest thing between tapping
    /// Focus and seeing it.
    private static var lastSyncedAt: Date?
    private static let minimumInterval: TimeInterval = 20

    func sync(force: Bool = false) async {
        // Every monitor this registers is something that would fire and rebuild what the
        // debug kill just tore down. It runs on launch and on every visit to a list, so it
        // is the surest way for a kill to undo itself.
        #if DEBUG
        guard !DebugKillSwitch.isKilled else {
            print("Schedules not synced: debug kill switch is on")
            return
        }
        #endif

        if !force, let last = Self.lastSyncedAt, Date().timeIntervalSince(last) < Self.minimumInterval {
            return
        }
        Self.lastSyncedAt = Date()

        await syncRules()
        await syncAutoFocus()
        await syncUsageMilestones()
        await syncStreakReminder()

        guard let routines = try? await repository.routines() else { return }

        let snapshots: [RoutineScheduleSnapshot] = routines.compactMap { routine in
            for trigger in routine.triggers {
                if case .schedule(let schedule) = trigger, !schedule.weekdays.isEmpty {
                    return RoutineScheduleSnapshot(routine: routine, schedule: schedule)
                }
            }
            return nil
        }

        do {
            try appGroupStore.saveRoutineScheduleSnapshots(snapshots)
            try await deviceActivityService.syncRoutineSchedules(snapshots)
            print("Synced \(snapshots.count) scheduled routine(s) for background start")
        } catch {
            print("Routine schedule sync failed: \(error.localizedDescription)")
        }

        await syncStartAlarms(routines: routines)
    }

    /// Books tonight's streak reminder, or withdraws it.
    ///
    /// On every sync rather than only when the streak screen is opened: the reminder is
    /// for the evening of a day that has not been earned, and most such days are days
    /// nobody opened that screen.
    private func syncStreakReminder() async {
        let executions = (try? await routineExecutionRepository.executions(from: nil, to: nil)) ?? []
        let calendar = Calendar.current
        let routineDays = Set(executions.map { DayKey(date: $0.startedAt, calendar: calendar) })

        let summary = await Task.detached(priority: .utility) {
            StreakCalculator().summary(routineDays: routineDays, calendar: calendar)
        }.value

        StreakReminderScheduler().refresh(
            isTodayEarned: summary.isTodayEarned,
            current: summary.current
        )
    }

    /// Sets the "you have passed yesterday" watches on the couple of apps where passing
    /// yesterday would mean anything.
    ///
    /// Yesterday's own report is the bar. Apps that barely registered yesterday are left
    /// out: clearing four minutes says more about yesterday than about today.
    private func syncUsageMilestones() async {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date()

        guard let snapshot = try? appGroupStore.loadScreenTimeReportSnapshot(for: DayKey(date: yesterday)) else {
            return
        }

        let milestones = snapshot.applications
            .filter { $0.totalActivityDuration >= Double(UsageMilestoneNotice.minimumMinutes) * 60 }
            .sorted { $0.totalActivityDuration > $1.totalActivityDuration }
            .prefix(UsageMilestoneNotice.maximumWatched)
            .compactMap { application -> UsageMilestone? in
                guard let token = application.app.applicationToken else { return nil }
                return UsageMilestone(
                    appID: application.app.id,
                    token: token,
                    minutes: Int(application.totalActivityDuration / 60)
                )
            }

        do {
            try await deviceActivityService.syncUsageMilestones(Array(milestones))
        } catch {
            print("Usage milestone sync failed: \(error.localizedDescription)")
        }
    }

    /// Keeps AutoFocus watching whatever is currently marked as distracting.
    ///
    /// Here rather than at the moment the list is edited, because the list is edited from
    /// three places -- the picker, the breakdown's pencil, a routine's own choices -- and
    /// one of them will always be the one that forgot to re-register.
    private func syncAutoFocus() async {
        let configuration = appGroupStore.loadAutoFocusConfiguration()
        do {
            try await deviceActivityService.syncAutoFocus(configuration)
        } catch {
            print("AutoFocus sync failed: \(error.localizedDescription)")
        }
    }

    /// Books the alarm that rings before each scheduled routine, and cancels the ones
    /// that no longer have anything to warn about.
    ///
    /// Rebooked on every sync rather than once when the routine is saved: an alarm is a
    /// fixed date, so yesterday's has already fired and next week's is the one that
    /// matters. Cancelling first is what stops a routine whose time was edited from
    /// carrying an alarm for a moment it no longer starts.
    private func syncStartAlarms(routines: [Routine]) async {
        for routine in routines {
            guard routine.startAlarmEnabled,
                  routine.startAlarmLeadMinutes > 0,
                  let start = nextScheduledStart(for: routine)
            else {
                await alarmService.cancelRoutineStartAlarm(routineID: routine.id)
                continue
            }

            let firesAt = start.addingTimeInterval(-Double(routine.startAlarmLeadMinutes) * 60)
            try? await alarmService.scheduleRoutineStartAlarm(for: routine, firingAt: firesAt)
        }
    }

    /// The next moment this routine is due to begin, within the week ahead.
    private func nextScheduledStart(for routine: Routine) -> Date? {
        var candidates: [Date] = []

        for trigger in routine.triggers {
            guard case .schedule(let schedule) = trigger, !schedule.weekdays.isEmpty else { continue }

            var calendar = Calendar.current
            calendar.timeZone = TimeZone(identifier: schedule.timeZoneIdentifier) ?? .current
            let now = Date()
            let startOfToday = calendar.startOfDay(for: now)

            for offset in 0...7 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: startOfToday) else { continue }
                let weekdayValue = calendar.component(.weekday, from: day)
                guard let weekday = Weekday(rawValue: weekdayValue), schedule.weekdays.contains(weekday) else {
                    continue
                }

                var components = calendar.dateComponents([.year, .month, .day], from: day)
                components.hour = schedule.hour
                components.minute = schedule.minute
                components.second = 0

                if let date = calendar.date(from: components), date > now {
                    candidates.append(date)
                    break
                }
            }
        }

        return candidates.min()
    }
}
