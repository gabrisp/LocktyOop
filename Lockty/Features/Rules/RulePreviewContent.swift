import FamilyControls
import ManagedSettings
import SwiftUI

/// A limit rule at rest: what it measures, what it allows, and what it shuts.
///
/// The third of these, after routines and frictions, and for the same reason. A schedule
/// rule already had one -- it borrows the routine's -- while opening a usage or open-count
/// rule dropped you into its form, so the three kinds of rule read as three unrelated
/// screens when only one of them is really different.
struct RulePreviewContent: View {
    @ObservedObject var viewModel: RuleEditorViewModel
    let applicationTokens: [ApplicationToken]

    private var kind: RuleKind? { viewModel.kind }

    var body: some View {
        VStack(spacing: LocktySpacing.lg) {
            badge

            VStack(spacing: 2) {
                Text(subtitleLine)
                    .font(.system(.subheadline, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.secondaryText)
                    .lineLimit(1)

                Text(viewModel.name)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(LocktyColors.primaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }

            summaryCard
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, LocktySpacing.lg)
        .padding(.top, LocktySpacing.sm)
        .padding(.bottom, LocktySpacing.md)
    }

    private var badge: some View {
        Image(systemName: symbolName)
            .font(.system(size: 24, weight: .regular))
            .foregroundStyle(LocktyColors.primaryText)
            .padding(.horizontal, LocktySpacing.xl)
            .padding(.vertical, LocktySpacing.md)
            .overlay {
                Capsule(style: .continuous)
                    .stroke(LocktyColors.cardStroke, lineWidth: 1)
            }
    }

    private var symbolName: String {
        switch kind {
        case .openCountLimit: "lock"
        case .dailyUsageLimit: "hourglass"
        case .sessionDurationLimit: "timer"
        case .schedule: "calendar"
        case .none: "slider.horizontal.3"
        }
    }

    private var subtitleLine: String {
        guard let kind else { return "Rule" }
        return "Rule · \(kind.title)"
    }

    private var summaryCard: some View {
        VStack(spacing: 0) {
            // The limit itself first: it is the whole reason the rule exists, and the
            // apps below it are only where it applies.
            row(title: limitTitle, value: limitValue)

            divider

            row(title: "Blocks") {
                HStack(spacing: LocktySpacing.sm) {
                    if !applicationTokens.isEmpty {
                        LocktyStackedAppTokens(tokens: applicationTokens)
                    }
                    Text(blockedText)
                }
            }

            divider

            row(title: "Friction", value: viewModel.selectedFriction?.name ?? "None")

            divider

            row(title: "Unlocks allowed", value: viewModel.breaksAllowed ? "Yes" : "No")
        }
        .padding(.horizontal, LocktySpacing.md)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LocktyColors.ink(0.055))
        )
        .locktyImperfectBorder(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    /// Named after what it counts rather than after the rule, so the row reads as a
    /// measurement -- "App opens: 5 per day" -- and not as the rule repeating itself.
    private var limitTitle: String {
        switch kind {
        case .openCountLimit: "App opens"
        case .dailyUsageLimit: "Usage time"
        case .sessionDurationLimit: "Session time"
        case .schedule, .none: "Limit"
        }
    }

    private var limitValue: String {
        switch kind {
        case .openCountLimit:
            let opens = viewModel.maximumOpens
            return opens == 1 ? "1 per day" : "\(opens) per day"
        case .dailyUsageLimit:
            return "\(viewModel.maximumDailyMinutes) min per day"
        case .sessionDurationLimit:
            return "\(viewModel.maximumSessionMinutes) min per session"
        case .schedule, .none:
            return "—"
        }
    }

    private var blockedText: String {
        let apps = viewModel.selectionPreview.applicationTokens.count
        let categories = viewModel.selectionPreview.categoryTokens.count
        let groups = viewModel.selectedAppGroupIDs.count

        return RestrictionSummary.appsCategoriesAndGroups(
            apps: apps,
            categories: categories,
            groups: groups
        ) ?? "Nothing yet"
    }

    private func row(title: String, value: String) -> some View {
        row(title: title) { Text(value) }
    }

    private func row<Value: View>(
        title: String,
        @ViewBuilder value: () -> Value
    ) -> some View {
        HStack(spacing: LocktySpacing.md) {
            Text(title)
                .font(.system(.body, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.primaryText)

            Spacer(minLength: LocktySpacing.sm)

            value()
                .font(.system(.body, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.secondaryText)
                .lineLimit(1)
        }
        .frame(minHeight: 56)
    }

    private var divider: some View {
        Divider()
            .overlay(LocktyColors.separator.opacity(0.45))
    }
}
