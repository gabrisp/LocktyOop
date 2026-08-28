import SwiftUI

struct RoutineCard: View {
    let routine: Routine
    let isActive: Bool
    let onStart: () -> Void
    let onOpen: () -> Void

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Button(action: onOpen) {
                CardView(interactive: true) {
                    VStack(alignment: .leading, spacing: LocktySpacing.lg) {
                        HStack(spacing: LocktySpacing.md) {
                            Image(systemName: routine.icon ?? "repeat")
                                .font(.system(size: 22, weight: .semibold))
                                .frame(width: 44, height: 44)
                                .safeGlass(radius: 22)

                            Text(routine.name)
                                .font(LocktyTypography.headline)
                                .foregroundStyle(LocktyColors.primaryText)

                            Spacer()

                            BadgeView(
                                title: isActive ? "Active" : routine.mode.title,
                                color: isActive ? LocktyColors.productive : LocktyColors.primaryText
                            )
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .tappable()

            PrimaryButton(isActive ? "Running" : "Start", systemImage: "play.fill", action: onStart)
                .padding(.trailing, LocktySpacing.md)
                .padding(.bottom, LocktySpacing.md)
                .disabled(isActive)
                .opacity(isActive ? 0.6 : 1)
        }
    }
}
