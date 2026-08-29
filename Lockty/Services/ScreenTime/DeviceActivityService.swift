import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

protocol DeviceActivityServicing {
    func schedulePauseRelock(_ allowance: ActivePauseAllowance) async throws
    func scheduleBreakEnd(_ activeBreak: ActiveBreak) async throws
    func syncRoutineSchedules(_ snapshots: [RoutineScheduleSnapshot]) async throws
    /// Drops every allowance monitor, whatever it was counting.
    func cancelPauseRelocks() async
}

struct LiveDeviceActivityService: DeviceActivityServicing {
    private let center = DeviceActivityCenter()
    private let selectionStore: ScreenTimeSelectionStore

    init(selectionStore: ScreenTimeSelectionStore = ScreenTimeSelectionStore()) {
        self.selectionStore = selectionStore
    }

    /// Name of the usage event that ends an allowance.
    static let pauseAllowanceEvent = DeviceActivityEvent.Name("lockty.pause.allowance")

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

    func scheduleBreakEnd(_ activeBreak: ActiveBreak) async throws {
        let name = DeviceActivityName("lockty.break.\(activeBreak.id.uuidString)")
        let calendar = Calendar.current
        let start = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: activeBreak.startedAt)
        let end = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: activeBreak.endsAt)
        try center.startMonitoring(name, during: DeviceActivitySchedule(intervalStart: start, intervalEnd: end, repeats: false))
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
