import Foundation
import DeviceActivity

protocol DeviceActivityServicing {
    func schedulePauseRelock(_ allowance: ActivePauseAllowance) async throws
    func scheduleBreakEnd(_ activeBreak: ActiveBreak) async throws
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
}
