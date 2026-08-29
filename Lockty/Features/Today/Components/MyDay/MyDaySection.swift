import SwiftUI

struct MyDaySection: View {
    let activities: [DigitalActivity]

    @State private var inspectedActivity: DigitalActivity?

    private let rowHeight: CGFloat = 44

    private var orderedActivities: [DigitalActivity] {
        activities.sorted { $0.startDate < $1.startDate }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LocktySpacing.sm) {
            Text("MY DAY")
                .locktyEyebrow()
                .padding(.top, 16)

            if activities.isEmpty {
                CardView(radius: LocktyRadius.medium, padding: LocktySpacing.md) {
                    EmptyStateView(
                        title: "No day events yet",
                        message: "Lockty will surface routines, pauses and focus periods here when they exist for this day.",
                        systemImage: "timeline.selection"
                    )
                }
            } else {
                CardView(radius: LocktyRadius.medium, padding: LocktySpacing.md) {
                    HStack(alignment: .top, spacing: LocktySpacing.md) {
                        VStack(spacing: 0) {
                            ForEach(orderedActivities) { activity in
                                Text(activity.startDate, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                                    .font(.caption.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(LocktyColors.primaryText)
                                    .frame(height: rowHeight)
                            }
                        }

                        VStack(spacing: 0) {
                            ForEach(orderedActivities) { activity in
                                Rectangle()
                                    .fill(color(for: activity.type))
                                    .frame(width: 4, height: rowHeight)
                            }
                        }
                        .clipShape(Capsule())

                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(orderedActivities) { activity in
                                VStack(alignment: .leading, spacing: LocktySpacing.xs) {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(activity.title)
                                            .font(LocktyTypography.headline)
                                            .foregroundStyle(LocktyColors.primaryText)
                                            .lineLimit(1)

                                        Spacer(minLength: LocktySpacing.sm)

                                        Text(durationText(for: activity))
                                            .font(LocktyTypography.caption)
                                            .monospacedDigit()
                                            .foregroundStyle(LocktyColors.secondaryText)
                                            .locktyNumericTransition(trigger: activity.duration)
                                    }

                                    Text(detail(for: activity))
                                        .font(LocktyTypography.caption)
                                        .foregroundStyle(LocktyColors.secondaryText)
                                        .lineLimit(1)
                                }
                                .frame(height: rowHeight, alignment: .top)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    inspectedActivity = activity
                                }
                            }
                        }
                    }
                }
            }
        }
        .sheet(item: $inspectedActivity) { activity in
            LocktyDynamicSheet {
                MyDayActivityDetail(
                    activity: activity,
                    detail: detail(for: activity),
                    durationText: durationText(for: activity),
                    color: color(for: activity.type)
                )
            }
            .presentationDragIndicator(.visible)
        }
    }

    /// An activity still running shows NOW rather than a duration that would read 0m
    /// for something that just started.
    private func durationText(for activity: DigitalActivity) -> String {
        activity.endDate > Date() ? "NOW" : LocktyDurationFormatter.abbreviated(activity.duration)
    }

    private func detail(for activity: DigitalActivity) -> String {
        if let productivityScore = activity.productivityScore {
            return "\(Int(productivityScore.rounded()))% productive"
        }

        let appNames = activity.relatedApplications.map(\.displayName).prefix(2).joined(separator: " - ")
        return appNames.isEmpty ? activity.type.title : appNames
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

private struct MyDayActivityDetail: View {
    let activity: DigitalActivity
    let detail: String
    let durationText: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: LocktySpacing.md) {
            HStack(spacing: LocktySpacing.md) {
                Capsule()
                    .fill(color)
                    .frame(width: 4, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.title)
                        .font(.title3.weight(.regular))
                        .foregroundStyle(LocktyColors.primaryText)
                        .lineLimit(2)

                    Text(activity.type.title)
                        .font(LocktyTypography.caption)
                        .foregroundStyle(LocktyColors.secondaryText)
                }

                Spacer(minLength: 0)
            }

            VStack(spacing: LocktySpacing.sm) {
                detailRow(
                    "Started",
                    activity.startDate.formatted(date: .omitted, time: .shortened)
                )
                detailRow("Duration", durationText)
                detailRow("Detail", detail)
            }
        }
        .padding(LocktySpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(LocktyColors.secondaryText)
            Spacer(minLength: LocktySpacing.md)
            Text(value)
                .foregroundStyle(LocktyColors.primaryText)
                .multilineTextAlignment(.trailing)
        }
        .font(LocktyTypography.callout)
    }
}
