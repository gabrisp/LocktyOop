import SwiftUI

/// One insight, shaped like a notification.
///
/// A glyph, a line in bold and a line under it -- the shape everyone already knows how to
/// read at a glance, which is the whole reason for using it. It is not tappable: there is
/// nowhere it would lead that the cards below do not already go, and a card that looks
/// like a button and does nothing is worse than one that plainly does not.
struct TodayInsightCard: View {
    let insight: TodayInsight

    private var tint: Color {
        switch insight.tone {
        case .good: LocktyColors.productive
        case .neutral: LocktyColors.neutral
        case .warning: LocktyColors.unproductive
        }
    }

    var body: some View {
        CardView(radius: LocktyRadius.medium, padding: LocktySpacing.lg) {
            HStack(alignment: .top, spacing: LocktySpacing.md) {
                Image(systemName: insight.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background {
                        Circle().fill(tint.opacity(0.14))
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text(insight.title)
                        .font(.system(.subheadline, design: .default, weight: .semibold))
                        .foregroundStyle(LocktyColors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(insight.message)
                        .font(.system(.footnote, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
        }
    }
}
