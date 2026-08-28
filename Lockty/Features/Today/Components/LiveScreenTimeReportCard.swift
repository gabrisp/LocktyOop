import DeviceActivity
import _DeviceActivity_SwiftUI
import SwiftUI

/// This report view is the privacy-preserving fallback path when the app
/// doesn't have direct `DeviceActivityData` access for the selected day yet.
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
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let end = min(dayEnd, Date())
        return DeviceActivityFilter(
            segment: .hourly(during: DateInterval(start: start, end: end)),
            devices: nil,
            applications: [],
            categories: [],
            webDomains: []
        )
    }

    var body: some View {
        DeviceActivityReport(
            .locktyTotalActivity,
            filter: filter
        )
        .id(DayKey(date: day).id)
        .task(id: DayKey(date: day).id) {
            print("Rendering DeviceActivityReport for \(DayKey(date: day).id)")
        }
    }
}
