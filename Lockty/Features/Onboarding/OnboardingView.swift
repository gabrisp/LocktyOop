import SwiftUI

struct OnboardingView: View {
    let authorizationState: ScreenTimeAuthorizationState
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LocktySpacing.xl) {
            Spacer()

            VStack(alignment: .leading, spacing: LocktySpacing.md) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.tint)

                Text("Build calmer defaults")
                    .font(LocktyTypography.largeTitle)
                    .foregroundStyle(LocktyColors.primaryText)

                Text("Lockty uses Apple Screen Time APIs to help you start routines, block distractions, and pause before impulsive app opens.")
                    .font(LocktyTypography.body)
                    .foregroundStyle(LocktyColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            CardView {
                VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                    Text("Screen Time")
                        .font(LocktyTypography.headline)
                        .foregroundStyle(LocktyColors.primaryText)

                    Text(authorizationState.title)
                        .font(LocktyTypography.callout)
                        .foregroundStyle(LocktyColors.secondaryText)
                }
            }

            PrimaryButton("Continue", systemImage: "arrow.right", action: onContinue)
        }
        .padding(LocktySpacing.xl)
        .locktyScreenBackground()
    }
}
