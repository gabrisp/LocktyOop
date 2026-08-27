import SwiftUI

struct DigitalActivityCard: View {
    let activity: DigitalActivity

    var body: some View {
        CardView(radius: LocktyRadius.medium, padding: LocktySpacing.md) {
            HStack(alignment: .top, spacing: LocktySpacing.md) {
                VStack(spacing: LocktySpacing.xs) {
                    Text(activity.startDate, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(LocktyColors.primaryText)

                    Capsule()
                        .fill(typeColor)
                        .frame(width: 4, height: 34)
                }
                .frame(width: 48)

                VStack(alignment: .leading, spacing: LocktySpacing.xs) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(activity.title)
                            .font(LocktyTypography.headline)
                            .foregroundStyle(LocktyColors.primaryText)
                            .lineLimit(1)

                        Spacer(minLength: LocktySpacing.sm)

                        Text(LocktyDurationFormatter.abbreviated(activity.duration))
                            .font(LocktyTypography.caption)
                            .monospacedDigit()
                            .foregroundStyle(LocktyColors.secondaryText)
                            .locktyNumericTransition(trigger: activity.duration)
                    }

                    Text(detailText)
                        .font(LocktyTypography.caption)
                        .foregroundStyle(LocktyColors.secondaryText)
                        .locktyNumericTransition(trigger: detailText)
                        .lineLimit(2)
                }
            }
        }
    }

    private var detailText: String {
        if let productivityScore = activity.productivityScore {
            return "\(Int(productivityScore.rounded()))% productive"
        }

        let appNames = activity.relatedApplications.map(\.displayName).prefix(2).joined(separator: " - ")
        return appNames.isEmpty ? activity.type.title : appNames
    }

    private var typeColor: Color {
        switch activity.type {
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
