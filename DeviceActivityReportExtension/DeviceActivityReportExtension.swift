import DeviceActivity
import _DeviceActivity_SwiftUI
import ExtensionKit
import SwiftUI

@main
struct LocktyDeviceActivityReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        LocktyTotalActivityReport { configuration in
            LocktyTotalActivityView(configuration: configuration)
        }
    }
}
