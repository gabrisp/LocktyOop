import SwiftUI

struct LoadingView: View {
    var body: some View {
        VStack(spacing: LocktySpacing.md) {
            ProgressView()
            Text("Loading")
                .font(LocktyTypography.callout)
                .foregroundStyle(LocktyColors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
