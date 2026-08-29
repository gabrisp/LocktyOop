import FamilyControls
import ManagedSettings
import SwiftUI

/// The card for a routine that is running right now. Only on screen while one is: with
/// nothing active there is nothing to unlock, so it isn't rendered at all.
struct ActiveModeCard: View {
    let routine: ActiveRoutine
    let tokens: [ApplicationToken]
    /// The allowance running right now, so the app it released shows its timer instead
    /// of a lock.
    var allowance: ActivePauseAllowance?
    let onOpenApps: () -> Void
    let onUnlock: (ApplicationToken) -> Void

    private var radius: CGFloat { LocktyRadius.medium }

    /// The one app the running allowance has released, if it is one of these.
    private var releasedToken: ApplicationToken? {
        guard let allowance else { return nil }
        return tokens.first { AppIdentity.ID(token: $0) == allowance.context.appID }
    }

    private var blockedCountText: String {
        let count = tokens.isEmpty ? routine.shieldPolicy.blockedApplications.count : tokens.count
        return count == 1 ? "1 App bloqueada" : "\(count) Apps bloqueadas"
    }

    var body: some View {
        CardView(radius: radius, padding: LocktySpacing.lg) {
            VStack(alignment: .leading, spacing: LocktySpacing.md) {
                LocktySectionTitle("Mis Apps", onOpen: onOpenApps)

                HStack(spacing: LocktySpacing.md) {
                    Image(systemName: "shield.fill")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(LocktyColors.productive)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(routine.nameSnapshot)
                            .font(.system(.headline, design: .default, weight: .bold))
                            .foregroundStyle(LocktyColors.primaryText)
                            .lineLimit(1)

                        Text(blockedCountText)
                            .font(.system(.subheadline, design: .default, weight: .regular))
                            .foregroundStyle(LocktyColors.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }

                Divider()
                    .overlay(LocktyColors.cardStroke)

                blockedApps
            }
        }
    }

    /// The blocked apps, each behind a lock, with the row's own unlock button floating
    /// over the middle of it.
    private var blockedApps: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LocktySpacing.lg) {
                ForEach(tokens, id: \.self) { token in
                    let released = releasedToken == token

                    Button {
                        onUnlock(token)
                    } label: {
                        LocktyAppLockBadge(
                            token: token,
                            unlockedFrom: released ? allowance?.startedAt : nil,
                            unlockedUntil: released ? allowance?.expiresAt : nil,
                            caption: released ? .remainingTime : .action("Desbloquear")
                        )
                    }
                    .buttonStyle(.plain)
                    .tappable()
                }
            }
            .padding(.horizontal, LocktySpacing.lg)
        }
        .scrollIndicators(.hidden)
        // Cancels the card's own padding so the row runs to the card's edges, then puts
        // it back inside the content -- otherwise the icons stop short and the row reads
        // as clipped rather than scrollable.
        .padding(.horizontal, -LocktySpacing.lg)
        .overlay {
            // Floating over the row rather than under it: it is the shortcut for the
            // whole set, and the per-app buttons behind it stay reachable either side.
            Button(action: onOpenApps) {
                Label {
                    Text("Desbloquear apps")
                        .font(.system(.headline, design: .default, weight: .regular))
                } icon: {
                    Image(systemName: "lock.open.fill")
                        .font(.system(size: 15, weight: .regular))
                }
                .foregroundStyle(.black)
                .padding(.horizontal, LocktySpacing.lg)
                .padding(.vertical, LocktySpacing.md)
                .background(Capsule(style: .continuous).fill(.white))
            }
            .buttonStyle(.plain)
            .tappable()
        }
    }
}
