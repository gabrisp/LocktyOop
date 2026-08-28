import SwiftUI

struct MyDaySection: View {
    let activities: [DigitalActivity]

    var body: some View {
        VStack(alignment: .leading, spacing: LocktySpacing.sm) {
            SectionHeader(title: "My Day")

            if activities.isEmpty {
                CardView(radius: LocktyRadius.medium, padding: LocktySpacing.md) {
                    EmptyStateView(
                        title: "No day events yet",
                        message: "Lockty will surface routines, pauses and focus periods here when they exist for this day.",
                        systemImage: "timeline.selection"
                    )
                }
            } else {
                VStack(spacing: LocktySpacing.sm) {
                    ForEach(activities) { activity in
                        DigitalActivityCard(activity: activity)
                    }
                }
            }
        }
    }
}
