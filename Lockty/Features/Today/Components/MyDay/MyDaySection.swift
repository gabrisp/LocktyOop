import SwiftUI

struct MyDaySection: View {
    let activities: [DigitalActivity]

    var body: some View {
        VStack(alignment: .leading, spacing: LocktySpacing.sm) {
            SectionHeader(title: "My Day")

            VStack(spacing: LocktySpacing.sm) {
                ForEach(activities) { activity in
                    DigitalActivityCard(activity: activity)
                }
            }
        }
    }
}
