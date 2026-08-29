import FamilyControls
import ManagedSettings
import SwiftUI

/// The card that surfaces an unlock request the shield wrote while Lockty was closed.
///
/// It sits above everything else on Today and announces itself with an aura that burns
/// for a couple of seconds and then settles, so it is impossible to miss on arrival
/// without leaving a permanently loud card on the screen. Answering it is what opens the
/// pause flow -- the shield's button only asks.
struct UnlockRequestCard: View {
    let context: PauseContext
    let onUnlock: () -> Void

    /// Drives the arrival glow. It fades once and stays settled; nothing re-triggers it
    /// while the same request is on screen.
    @State private var isAnnouncing = true

    private var radius: CGFloat { LocktyRadius.medium }

    private var token: ApplicationToken? {
        context.applicationToken
    }

    var body: some View {
        CardView(radius: radius, padding: LocktySpacing.lg) {
            VStack(alignment: .leading, spacing: LocktySpacing.lg) {
                Label {
                    Text("Solicitud de desbloqueo")
                        .font(.system(.subheadline, design: .default, weight: .semibold))
                } icon: {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(LocktyColors.productive)

                HStack(spacing: LocktySpacing.md) {
                    appIcon

                    VStack(alignment: .leading, spacing: 2) {
                        Text("¿Desbloquear esta app?")
                            .font(.system(.headline, design: .default, weight: .semibold))
                            .foregroundStyle(LocktyColors.primaryText)
                            .lineLimit(1)

                        Text(context.displayName)
                            .font(.system(.subheadline, design: .default, weight: .regular))
                            .foregroundStyle(LocktyColors.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }

                Button(action: onUnlock) {
                    Label {
                        Text("Desbloquear")
                            .font(.system(.headline, design: .default, weight: .regular))
                    } icon: {
                        Image(systemName: "lock.open")
                            .font(.system(size: 15, weight: .regular))
                    }
                    .foregroundStyle(LocktyColors.primaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, LocktySpacing.md)
                    .contentShape(Rectangle())
                    .safeGlass(radius: radius - LocktySpacing.lg, interactive: true)
                }
                .buttonStyle(.plain)
                .tappable()
            }
        }
        // The aura is a stroke that blurs outwards, not a shadow: it has to read as the
        // card's own edge lighting up rather than as something cast behind it.
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(LocktyColors.productive, lineWidth: isAnnouncing ? 2 : 0.6)
                .blur(radius: isAnnouncing ? 7 : 0)
                .opacity(isAnnouncing ? 0.9 : 0.25)
                .allowsHitTesting(false)
        }
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(LocktyColors.productive.opacity(isAnnouncing ? 0.9 : 0.3), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .task(id: context.id) {
            isAnnouncing = true
            try? await Task.sleep(for: .seconds(2.4))
            withAnimation(.smooth(duration: 0.9)) {
                isAnnouncing = false
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: context.id)
    }

    /// The same badge the active mode card uses, so a blocked app looks the same
    /// wherever it is shown.
    private var appIcon: some View {
        LocktyAppLockBadge(token: token, scale: 1.25)
    }
}
