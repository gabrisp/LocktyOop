import SwiftUI

struct DailyPerspectiveCard: View {
    let perspective: DailyPerspective

    var body: some View {
        CardView(radius: LocktyRadius.large, padding: LocktySpacing.lg) {
            VStack(alignment: .leading, spacing: LocktySpacing.md) {
                Text("DAILY PERSPECTIVE")
                    .font(LocktyTypography.caption)
                    .foregroundStyle(LocktyColors.tertiaryText)

                Text(perspective.title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(LocktyColors.primaryText)

                Text(perspective.body)
                    .font(LocktyTypography.body)
                    .foregroundStyle(LocktyColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
