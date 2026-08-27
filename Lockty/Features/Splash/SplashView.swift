import SwiftUI

struct SplashView: View {
    var body: some View {
        VStack(spacing: LocktySpacing.lg) {
            Image(systemName: "lock.shield")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(.tint)

            Text("Lockty")
                .font(LocktyTypography.largeTitle)
                .foregroundStyle(LocktyColors.primaryText)

            Text("Restoring your focus state")
                .font(LocktyTypography.callout)
                .foregroundStyle(LocktyColors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .locktyScreenBackground()
    }
}
