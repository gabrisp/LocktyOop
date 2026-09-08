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
    let onUnlock: (ApplicationToken) -> Void
    /// The heading's chevron: routines live on Focus, and the card is a window onto them.
    /// Nil on Focus itself, where the chevron would point at the screen it is already on.
    var onOpenSection: (() -> Void)?
    /// Tapped on an app the allowance has already let out. There is nothing to unlock,
    /// so this shows what is left of it instead of reopening the flow.
    var onShowAllowance: ((ApplicationToken) -> Void)?

    private var radius: CGFloat { LocktyRadius.medium }

    private var releasedIDs: Set<AppIdentity.ID> {
        allowance?.releasedApplications ?? []
    }

    /// How one routine's badges are drawn: green while a break can still be taken, red
    /// when it cannot -- with a clock only when there is a moment to wait for. A limit
    /// that has been reached has no such moment.
    ///
    /// Per routine, not per card. Each has its own break policy, count and cooldown, so
    /// one answer for the whole card put another routine's wait over apps it does not
    /// hold -- and showed a countdown on routines that never allowed breaks at all.
    private func badgeAvailability(
        for group: TodayActiveRoutineGroup
    ) -> LocktyAppLockBadge.Availability {
        switch group.availability {
        case .available:
            .unlockable
        case .unavailable(let unavailable):
            unavailable.retryAt.map { .cooldown(until: $0) } ?? .exhausted
        }
    }

    /// Everything this routine is holding, in one line.
    ///
    /// The apps were the whole of it, and they are the least of what a routine can be
    /// doing: one blocking a category through two groups, filtering the web and closing
    /// the App Store read as "3 Apps blocked" -- a line that is true and describes almost
    /// none of it.
    ///
    /// Only what is actually on. A list of everything a routine *could* close, with the
    /// unused ones greyed or named anyway, is a longer line saying less.
    private func subtitleText(for group: TodayActiveRoutineGroup) -> String {
        let routine = group.routine
        let policy = routine.shieldPolicy
        var parts: [String] = []

        let apps = group.tokens.isEmpty ? policy.blockedApplications.count : group.tokens.count
        if apps > 0 {
            parts.append(apps == 1 ? "1 App blocked" : "\(apps) Apps blocked")
        }

        // Named separately from the apps inside them: a group is a thing you made and
        // recognise, and folding it into a headcount hides the reason the number is what
        // it is.
        let groupCount = policy.selectionScopes.filter {
            if case .appGroup = $0 { return true } else { return false }
        }.count
        if groupCount > 0 {
            parts.append(groupCount == 1 ? "1 Group" : "\(groupCount) Groups")
        }

        if !policy.blockedDomains.isEmpty {
            parts.append(policy.blockedDomains.count == 1 ? "1 Site" : "\(policy.blockedDomains.count) Sites")
        }

        if policy.contentRestrictions.blocksAdultWebContent { parts.append("Adult content") }
        if policy.contentRestrictions.blocksITunesPurchases { parts.append("Purchases") }
        if policy.contentRestrictions.blocksAppInstallation { parts.append("Installs") }
        if routine.modeSnapshot == .strict { parts.append("Strict mode") }

        // A routine that closes nothing is not a state the app can reach, but a line that
        // is simply absent reads as something that failed to load.
        guard !parts.isEmpty else { return "Nothing blocked" }
        return parts.joined(separator: " · ")
    }

    /// The title says how many are running, so a second routine starting is visible in
    /// the heading rather than only in the list under it.
    private var headingTitle: String {
        visibleGroups.count > 1 ? "\(visibleGroups.count) Routines" : "Routine"
    }

    private var visibleGroups: [TodayActiveRoutineGroup] {
        state.phase == .active ? groups : []
    }

    var body: some View {
        CardView(radius: radius, padding: LocktySpacing.lg) {
            VStack(alignment: .leading, spacing: LocktySpacing.md) {
                // Eight more at the top, which lands this on the same 26 the usage card
                // gets from its own xl padding. Added here rather than by moving the card
                // to xl: that would widen the sides too, and the app row deliberately
                // cancels the horizontal padding to bleed to the card's edges.
                if let onOpenSection {
                    LocktySectionTitle(headingTitle, onOpen: onOpenSection)
                        .padding(.top, LocktySpacing.sm)
                } else {
                    // On Focus there is nowhere for the chevron to lead. The same heading,
                    // without the arrow and without a tap that would answer nothing.
                    LocktySectionTitle(headingTitle, showsChevron: false)
                        .padding(.top, LocktySpacing.sm)
                }

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
                        badge(for: token, in: group)
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
    private func badge(for token: ApplicationToken, in group: TodayActiveRoutineGroup) -> some View {
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
                availability: released ? .unlockable : badgeAvailability(for: group),
                caption: released ? .remainingTime : .action("Unlock")
            )
        }
        .buttonStyle(.locktyInteractive(brighten: true))
        .tappable()
    }
}
