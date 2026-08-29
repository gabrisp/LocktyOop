import SwiftUI

/// Entry point to a section that used to be a tab.
struct TodaySectionShortcut: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CardView(radius: LocktyRadius.medium, padding: LocktySpacing.md, interactive: true) {
                HStack(spacing: LocktySpacing.sm) {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(LocktyColors.primaryText)

                    Text(title)
                        .font(LocktyTypography.headline)
                        .foregroundStyle(LocktyColors.primaryText)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(.plain)
        .tappable()
    }
}
