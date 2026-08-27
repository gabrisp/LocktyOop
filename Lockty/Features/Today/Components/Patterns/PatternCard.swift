import SwiftUI

struct PatternCard: View {
    let pattern: BehaviorPattern

    var body: some View {
        CardView(radius: LocktyRadius.medium, padding: LocktySpacing.md) {
            VStack(alignment: .leading, spacing: LocktySpacing.xs) {
                Text(pattern.title)
                    .font(LocktyTypography.headline)
                    .foregroundStyle(LocktyColors.primaryText)

                Text(pattern.body)
                    .font(LocktyTypography.caption)
                    .foregroundStyle(LocktyColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
