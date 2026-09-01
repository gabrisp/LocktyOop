import FamilyControls
import ManagedSettings
import SwiftUI

/// The routine card on Today: every routine running right now, and everything they hold.
///
/// One card for all of them rather than one card each. They are the same fact -- what is
/// shut and why -- and a stack of near-identical cards would say it several times over.
/// Each routine gets its own line at the top, and the apps below are grouped by the
/// routine holding them, because two routines running at once are two separate reasons an
/// app is shut and an undivided row would claim they were one.
struct ActiveModeCard: View {
    let state: TodayRoutineCardState
    /// Every running routine with its own apps, in the order they started.
    var groups: [TodayActiveRoutineGroup] = []
    var activeRoutine: ActiveRoutine?
    var allowance: ActivePauseAllowance?
    var breakAvailability: BreakAvailability = .available
    let onUnlock: (ApplicationToken) -> Void
    /// The heading's chevron: routines live on Focus, and the card is a window onto them.
    let onOpenSection: () -> Void
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

    private func subtitleText(for group: TodayActiveRoutineGroup) -> String {
        let count = group.tokens.isEmpty
            ? group.routine.shieldPolicy.blockedApplications.count
            : group.tokens.count
        return count == 1 ? "1 App bloqueada" : "\(count) Apps bloqueadas"
    }

    /// The title says how many are running, so a second routine starting is visible in
    /// the heading rather than only in the list under it.
    private var headingTitle: String {
        visibleGroups.count > 1 ? "\(visibleGroups.count) Rutinas" : "Rutina"
    }

    private var visibleGroups: [TodayActiveRoutineGroup] {
        state.phase == .active ? groups : []
    }

    var body: some View {
        CardView(radius: radius, padding: LocktySpacing.lg) {
            VStack(alignment: .leading, spacing: LocktySpacing.md) {
                LocktySectionTitle(headingTitle, onOpen: onOpenSection)

                if visibleGroups.isEmpty {
                    routineRow(
                        icon: state.icon,
                        name: state.name,
                        detail: state.detailText
                    )
                } else {
                    VStack(alignment: .leading, spacing: LocktySpacing.md) {
                        ForEach(visibleGroups) { group in
                            routineRow(
                                icon: group.routine.iconSnapshot,
                                name: group.routine.nameSnapshot,
                                detail: subtitleText(for: group)
                            )
                        }
                    }
                }

                Divider()
                    .overlay(LocktyColors.cardStroke)

                blockedApps
            }
        }
    }

    private func routineRow(icon: String?, name: String, detail: String) -> some View {
        HStack(spacing: LocktySpacing.md) {
            Image(systemName: icon?.isEmpty == false ? icon! : "repeat")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(LocktyColors.productive)

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(.headline, design: .default, weight: .bold))
                    .foregroundStyle(LocktyColors.primaryText)
                    .lineLimit(1)

                Text(detail)
                    .font(.system(.subheadline, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
    }

    /// Every routine's apps in one row, each group separated by a rule.
    ///
    /// One scroll view rather than one per routine: they are all "what is shut right
    /// now", and stacking a second scroller under the first would make the reader work
    /// out that the two lists are the same kind of thing. The divider is what says where
    /// one routine's apps end.
    private var blockedApps: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LocktySpacing.lg) {
                ForEach(visibleGroups) { group in
                    ForEach(group.tokens, id: \.self) { token in
                        badge(for: token)
                    }

                    if group.id != visibleGroups.last?.id {
                        Divider()
                            .frame(height: 54)
                            .overlay(LocktyColors.cardStroke)
                    }
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

    /// One app behind a lock. Tapping it opens the unlock flow, or, when an allowance has
    /// already let it out, what is left of that allowance.
    private func badge(for token: ApplicationToken) -> some View {
        let released = releasedIDs.contains(AppIdentity.ID(token: token))

        return Button {
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
                // An app already out is out however the break policy stands: the
                // allowance running is the answer, not the cooldown that will apply to
                // the next request.
                availability: released ? .unlockable : badgeAvailability,
                caption: released ? .remainingTime : .action("Desbloquear")
            )
        }
        .buttonStyle(.locktyInteractive(brighten: true))
        .tappable()
    }
}
