import ManagedSettings
import SwiftUI

/// The limits holding something shut right now, and the apps they are holding.
///
/// A sibling of `ActiveModeCard` rather than a mode of it, and they look alike on purpose.
/// "A limit has run out" and "a routine is running" are the same fact from the reader's
/// side -- something is shut, there is a reason for it, and these are the apps -- but only
/// the routine had a card that named them. A limit said how much of the day was gone and
/// left you to work out which apps that had cost you.
///
/// Not `LimitsCard`, which is the day's arithmetic: what each limit has left. This one is
/// about the ones with nothing left.
struct ActiveLimitsCard: View {
    let groups: [TodayActiveLimitGroup]
    let onUnlock: (ApplicationToken) -> Void

    private var radius: CGFloat { LocktyRadius.medium }

    private var headingTitle: String {
        groups.count > 1 ? "\(groups.count) Limits" : "Limit"
    }

    var body: some View {
        CardView(radius: radius, padding: LocktySpacing.lg) {
            VStack(alignment: .leading, spacing: LocktySpacing.md) {
                LocktySectionTitle(headingTitle, showsChevron: false)
                    .padding(.top, LocktySpacing.sm)

                ForEach(groups) { group in
                    limitRow(group)
                }

                blockedApps
            }
        }
    }

    /// One limit's line: what it is called and what kind of limit it is.
    private func limitRow(_ group: TodayActiveLimitGroup) -> some View {
        HStack(spacing: LocktySpacing.md) {
            Image(systemName: "hourglass")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(LocktyColors.warning)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(.system(.headline, design: .default, weight: .bold))
                    .foregroundStyle(LocktyColors.primaryText)
                    .lineLimit(1)

                Text(group.detail)
                    .font(.system(.subheadline, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
    }

    /// Every limit's apps in one row, each group separated by a rule.
    ///
    /// One scroll view rather than one per limit, for the reason the routine card gives:
    /// they are all "what is shut right now", and a second scroller under the first would
    /// make the reader work out that the two lists are the same kind of thing.
    private var blockedApps: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LocktySpacing.lg) {
                ForEach(groups) { group in
                    ForEach(group.tokens, id: \.self) { token in
                        badge(for: token, in: group)
                    }

                    if group.id != groups.last?.id {
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

    /// One app behind a limit. Tapping it opens the unlock flow, exactly as it does on the
    /// routine card -- a limit that allows a break is asked for one the same way.
    private func badge(for token: ApplicationToken, in group: TodayActiveLimitGroup) -> some View {
        Button {
            onUnlock(token)
        } label: {
            LocktyAppLockBadge(
                token: token,
                availability: group.availability,
                // The badge draws "Blocked" of its own accord when there is nothing to
                // ask for, so one caption covers a limit that opens and one that does not.
                caption: .action("Unlock")
            )
        }
        .buttonStyle(.locktyInteractive(brighten: true))
        .tappable()
    }
}
