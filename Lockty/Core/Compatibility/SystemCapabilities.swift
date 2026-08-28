import Foundation

struct SystemCapabilities: Codable, Hashable {
    var supportsScreenTimeAuthorization: Bool
    var supportsAppBlocking: Bool
    var supportsDomainBlocking: Bool
    var supportsUsageReporting: Bool
    var supportsAlarmRoutineTriggers: Bool
    var supportsNFC: Bool
    var supportsLocationTriggers: Bool
    var supportsLiquidGlass: Bool
    var isRunningInSimulator: Bool

    static var current: SystemCapabilities {
        #if targetEnvironment(simulator)
        let simulator = true
        #else
        let simulator = false
        #endif

        return SystemCapabilities(
            supportsScreenTimeAuthorization: true,
            supportsAppBlocking: true,
            supportsDomainBlocking: true,
            supportsUsageReporting: true,
            supportsAlarmRoutineTriggers: ProcessInfo.processInfo.isOperatingSystemAtLeast(
                OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)
            ),
            supportsNFC: !simulator,
            supportsLocationTriggers: true,
            supportsLiquidGlass: ProcessInfo.processInfo.isOperatingSystemAtLeast(
                OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)
            ),
            isRunningInSimulator: simulator
        )
    }
}
