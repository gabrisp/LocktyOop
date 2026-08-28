import SwiftUI

struct EmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: LocktySpacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(LocktyColors.secondaryText)

            VStack(spacing: LocktySpacing.xs) {
                Text(title)
                    .font(LocktyTypography.headline)
                    .foregroundStyle(LocktyColors.primaryText)

                Text(message)
                    .font(LocktyTypography.callout)
                    .foregroundStyle(LocktyColors.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(LocktySpacing.xl)
    }
}
