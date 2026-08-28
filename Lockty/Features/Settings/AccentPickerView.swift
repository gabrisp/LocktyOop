import SwiftUI

struct AccentPickerView: View {
    let theme: ThemeManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        LocktyDynamicSheet {
            VStack(alignment: .leading, spacing: LocktySpacing.md) {
                EditorTopBar(title: "Accent", onClose: { dismiss() })

                VStack(spacing: LocktySpacing.sm) {
                    ForEach(LocktyAccent.allCases) { accent in
                        Button {
                            theme.selectAccent(accent)
                        } label: {
                            CardView(radius: LocktyRadius.medium, padding: LocktySpacing.md, interactive: true) {
                                HStack(spacing: LocktySpacing.md) {
                                    Circle()
                                        .fill(accent.color)
                                        .frame(width: 16, height: 16)

                                    Text(accent.title)
                                        .font(LocktyTypography.body)
                                        .foregroundStyle(LocktyColors.primaryText)

                                    Spacer()

                                    if theme.accent == accent {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(LocktyColors.primaryText)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .tappable()
                    }
                }
            }
            .padding(.horizontal, LocktySpacing.md)
            .padding(.top, LocktySpacing.sm)
            .padding(.bottom, LocktySpacing.md)
        }
    }
}
