import FamilyControls
import ManagedSettings
import SwiftUI

/// The card for a routine that is running right now. Only on screen while one is: with
/// nothing active there is nothing to unlock, so it isn't rendered at all.
struct ActiveModeCard: View {
    let routine: ActiveRoutine
    let tokens: [ApplicationToken]
    let onOpenApps: () -> Void
    let onUnlock: (ApplicationToken) -> Void

    private var radius: CGFloat { LocktyRadius.medium }

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
                    Button {
                        onUnlock(token)
                    } label: {
                        VStack(spacing: LocktySpacing.sm) {
                            ZStack {
                                Label(token)
                                    .labelStyle(.iconOnly)
                                    .id(token)
                                    .frame(width: 54, height: 54)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                                Image(systemName: "lock.fill")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.5), radius: 5)
                            }
                            .padding(4)
                            .overlay {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(LocktyColors.productive.opacity(0.7), lineWidth: 1.5)
                            }

                            Text("Desbloquear")
                                .font(.system(.caption, design: .default, weight: .regular))
                                .foregroundStyle(LocktyColors.productive)
                                .lineLimit(1)
                        }
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
