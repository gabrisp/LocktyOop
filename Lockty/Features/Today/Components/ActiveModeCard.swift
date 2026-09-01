import FamilyControls
import ManagedSettings
import SwiftUI

/// The routine card on Today. Active routines use the original locked-app badge row;
/// upcoming routines keep the same space without drawing apps.
struct ActiveModeCard: View {
    let state: TodayRoutineCardState
    var activeRoutine: ActiveRoutine?
    var tokens: [ApplicationToken] = []
    var allowance: ActivePauseAllowance?
    var breakAvailability: BreakAvailability = .available
    let onUnlock: (ApplicationToken) -> Void
    /// Tapped on an app the allowance has already let out. There is nothing to unlock,
    /// so this shows what is left of it instead of reopening the flow.
    var onShowAllowance: ((ApplicationToken) -> Void)?

    private var radius: CGFloat { LocktyRadius.medium }

    private var releasedIDs: Set<AppIdentity.ID> {
        allowance?.releasedApplications ?? []
    }

    /// How the badges are drawn: green while a break can still be taken, red when it
    /// cannot -- with a clock only when there is a moment to wait for. A limit that has
    /// been reached has no such moment, so it is red and silent.
    private var badgeAvailability: LocktyAppLockBadge.Availability {
        switch breakAvailability {
        case .available:
            .unlockable
        case .unavailable(let unavailable):
            unavailable.retryAt.map { .cooldown(until: $0) } ?? .exhausted
        }
    }

    private var subtitleText: String {
        guard let activeRoutine, state.phase == .active else { return state.detailText }
        let count = tokens.isEmpty ? activeRoutine.shieldPolicy.blockedApplications.count : tokens.count
        return count == 1 ? "1 App bloqueada" : "\(count) Apps bloqueadas"
    }

    var body: some View {
        CardView(radius: radius, padding: LocktySpacing.lg) {
            VStack(alignment: .leading, spacing: LocktySpacing.md) {
                LocktySectionTitle("Rutina", prominent: true)

                HStack(spacing: LocktySpacing.md) {
                    Image(systemName: state.icon?.isEmpty == false ? state.icon! : "repeat")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(LocktyColors.productive)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(state.name)
                            .font(.system(.headline, design: .default, weight: .bold))
                            .foregroundStyle(LocktyColors.primaryText)
                            .lineLimit(1)

                        Text(subtitleText)
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

    private var visibleTokens: [ApplicationToken] {
        state.phase == .active ? tokens : []
    }

    /// The blocked apps, each behind a lock. Tapping one opens the unlock flow for that
    /// app. Upcoming routines keep this row's height but draw it empty.
    private var blockedApps: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LocktySpacing.lg) {
                ForEach(visibleTokens, id: \.self) { token in
                    let released = releasedIDs.contains(AppIdentity.ID(token: token))

                    Button {
                        if released, let onShowAllowance {
                            onShowAllowance(token)
                        } else {
                            onUnlock(token)
                        }
                    } label: {
                        LocktyAppLockBadge(
                            token: token,
                            unlockedFrom: released ? allowance?.startedAt : nil,
                            unlockedUntil: released ? allowance?.expiresAt : nil,
                            // An app already out is out however the break policy stands:
                            // the allowance running is the answer, not the cooldown that
                            // will apply to the next request.
                            availability: released ? .unlockable : badgeAvailability,
                            caption: released ? .remainingTime : .action("Desbloquear")
                        )
                    }
                    .buttonStyle(.locktyInteractive(brighten: true))
                    .tappable()
                }
            }
            .frame(minHeight: 98, alignment: .leading)
            .padding(.horizontal, LocktySpacing.lg)
            .padding(.vertical, LocktySpacing.sm)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .padding(.horizontal, -LocktySpacing.lg)
    }
}
