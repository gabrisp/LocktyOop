import DeviceActivity
import _DeviceActivity_SwiftUI
import SwiftUI

/// The usage duration comes from Apple's DeviceActivityReport extension. The
/// main app cannot read Screen Time history directly through DeviceActivityCenter.
struct LiveScreenTimeReportCard: View {
    let day: Date

    var body: some View {
        CardView {
            VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                Text("Screen Time")
                    .font(LocktyTypography.headline)
                ScreenTimeReportLoaderView(day: day)
                .frame(minHeight: 54)
            }
        }
    }
}

struct ScreenTimeReportLoaderView: View {
    let day: Date

    private var filter: DeviceActivityFilter {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return DeviceActivityFilter(
            segment: .daily(during: DateInterval(start: start, end: end)),
            devices: .all
        )
    }

    var body: some View {
        DeviceActivityReport(
            .locktyTotalActivity,
            filter: filter
        )
        .id(DayKey(date: day).id)
    }
}
