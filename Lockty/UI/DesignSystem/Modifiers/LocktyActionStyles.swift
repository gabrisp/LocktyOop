import SwiftUI

extension View {
    func locktyPrimaryActionStyle() -> some View {
        modifier(LocktyActionButtonModifier(tint: LocktyColors.primaryText, foreground: Color(uiColor: .systemBackground)))
    }

    func locktySecondaryActionStyle() -> some View {
        modifier(LocktyActionButtonModifier(tint: nil, foreground: LocktyColors.primaryText))
    }

    func locktySheetDismissStyle() -> some View {
        self
            .font(.system(size: 18, weight: .ultraLight))
            .foregroundStyle(LocktyColors.primaryText)
            .frame(width: 46, height: 46)
            .contentShape(Circle())
            .clipShape(Circle())
            .safeGlass(radius: 23, interactive: true)
    }

    /// Small tracked-caps label above a value, e.g. "RESTRICTIONS", "SCHEDULE".
    func locktyEyebrow() -> some View {
        self
            .font(.system(size: 12, weight: .semibold))
            .tracking(0.06)
            .foregroundStyle(.secondary)
    }

    func locktyGlassInputStyle(height: CGFloat = 52) -> some View {
        self
            .font(LocktyTypography.body)
            .foregroundStyle(LocktyColors.primaryText)
            .padding(.horizontal, LocktySpacing.md)
            .frame(height: height)
            .safeGlass(radius: LocktyRadius.medium)
    }
}

private struct LocktyActionButtonModifier: ViewModifier {
    let tint: Color?
    let foreground: Color

    func body(content: Content) -> some View {
        content
            .fontWeight(.medium)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .contentShape(Rectangle())
            .safeGlass(
                radius: LocktyRadius.medium,
                interactive: true,
                tint: tint
            )
    }
}
