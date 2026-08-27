import SwiftUI

struct EditingDisabledBanner: View {
    let message: String

    var body: some View {
        CardView(radius: LocktyRadius.medium, padding: LocktySpacing.md) {
            HStack(spacing: LocktySpacing.md) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(LocktyColors.warning)

                VStack(alignment: .leading, spacing: LocktySpacing.xs) {
                    Text("Editing disabled")
                        .font(LocktyTypography.headline)
                        .foregroundStyle(LocktyColors.primaryText)
                    Text(message)
                        .font(LocktyTypography.caption)
                        .foregroundStyle(LocktyColors.secondaryText)
                }

                Spacer()
            }
        }
    }
}
