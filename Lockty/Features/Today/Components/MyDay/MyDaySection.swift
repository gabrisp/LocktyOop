import SwiftUI

struct MyDaySection: View {
    let activities: [DigitalActivity]

    private var orderedActivities: [DigitalActivity] {
        activities.sorted { $0.startDate < $1.startDate }
    }

    private var spanStart: Date? { orderedActivities.first?.startDate }
    private var spanEnd: Date? { orderedActivities.last?.endDate }

    private var totalDuration: TimeInterval {
        guard let spanStart, let spanEnd else { return 0 }
        return max(spanEnd.timeIntervalSince(spanStart), 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LocktySpacing.sm) {
            Text("MY DAY")
                .locktyEyebrow()

            if activities.isEmpty || totalDuration <= 0 {
                CardView(radius: LocktyRadius.medium, padding: LocktySpacing.md) {
                    EmptyStateView(
                        title: "No day events yet",
                        message: "Lockty will surface routines, pauses and focus periods here when they exist for this day.",
                        systemImage: "timeline.selection"
                    )
                }
            } else {
                CardView(radius: LocktyRadius.medium, padding: LocktySpacing.md) {
                    VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                        HStack(spacing: 2) {
                            ForEach(orderedActivities) { activity in
                                Rectangle()
                                    .fill(color(for: activity.type))
                                    .frame(width: max(CGFloat(activity.duration / totalDuration) * 320, 3))
                            }
                        }
                        .frame(height: 8)
                        .clipShape(Capsule())
                        .frame(maxWidth: .infinity)

                        HStack {
                            if let spanStart {
                                Text(spanStart, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                                    .monospacedDigit()
                            }
                            Spacer()
                            if let last = orderedActivities.last {
                                Text(last.title)
                                    .lineLimit(1)
                            }
                        }
                        .font(LocktyTypography.caption)
                        .foregroundStyle(LocktyColors.secondaryText)
                    }
                }
            }
        }
    }

    private func color(for type: DigitalActivityType) -> Color {
        switch type {
        case .routine, .focus:
            LocktyColors.productive
        case .detox:
            LocktyColors.neutral
        case .breakPeriod, .freeTime:
            LocktyColors.warning
        case .distraction:
            LocktyColors.unproductive
        }
    }
}
