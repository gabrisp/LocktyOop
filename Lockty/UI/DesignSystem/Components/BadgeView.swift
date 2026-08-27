import SwiftUI

struct BadgeView: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(LocktyTypography.caption)
            .foregroundStyle(color)
            .padding(.horizontal, LocktySpacing.sm)
            .padding(.vertical, LocktySpacing.xs)
            .background(color.opacity(0.14), in: Capsule())
    }
}
