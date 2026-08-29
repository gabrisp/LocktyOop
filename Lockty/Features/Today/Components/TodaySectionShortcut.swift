import SwiftUI

/// Routines / Pauses. These are buttons, not cards, so they take interactive glass
/// rather than the material a CardView paints.
struct TodaySectionShortcut: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
            .padding(LocktySpacing.md)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .safeGlass(radius: LocktyRadius.medium, interactive: true)
        }
        .buttonStyle(.plain)
        .tappable()
    }
}
