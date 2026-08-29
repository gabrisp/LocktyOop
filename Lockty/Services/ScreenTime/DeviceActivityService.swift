import Foundation
import DeviceActivity

protocol DeviceActivityServicing {
    func schedulePauseRelock(_ allowance: ActivePauseAllowance) async throws
    func scheduleBreakEnd(_ activeBreak: ActiveBreak) async throws
    func syncRoutineSchedules(_ snapshots: [RoutineScheduleSnapshot]) async throws
}

struct LiveDeviceActivityService: DeviceActivityServicing {
    private let center = DeviceActivityCenter()

    func schedulePauseRelock(_ allowance: ActivePauseAllowance) async throws {
        let name = DeviceActivityName("lockty.pause.\(allowance.id.uuidString)")
        let calendar = Calendar.current
        let start = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: allowance.startedAt)
        let end = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: allowance.expiresAt)
        try center.startMonitoring(name, during: DeviceActivitySchedule(intervalStart: start, intervalEnd: end, repeats: false))
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
