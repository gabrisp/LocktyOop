import FamilyControls
import ManagedSettings
import SwiftUI

/// A routine at rest: what it does, in one screen, with nothing to fill in.
///
/// This is what the editor shows before the pencil is pressed. It replaces a read-only
/// copy of the form, which was the same rows as the editor with the controls taken out --
/// so reading a routine looked like editing one that had stopped responding. A summary is
/// a different thing from a form: it answers "what does this do" rather than offering
/// every field it was built from.
struct RoutinePreviewContent: View {
    @ObservedObject var viewModel: RoutineEditorViewModel
    let applicationTokens: [ApplicationToken]
    /// Nil when the routine is not the one running.
    let activeSince: Date?
    /// The next scheduled start, when there is one and nothing is running.
    let nextStart: Date?

    private var accent: Color {
        LocktyColors.routine(viewModel.color)
    }

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

    /// The routine's own icon, and nothing else.
    ///
    /// It carried an arrow and a shield beside it. Every routine had the same two, so
    /// they said the same thing on every screen they appeared on -- which is to say
    /// nothing about the routine you are looking at.
    private var badge: some View {
        Image(systemName: viewModel.icon)
            .font(.system(size: 24, weight: .regular))
            .foregroundStyle(accent)
            .padding(.horizontal, LocktySpacing.xl)
            .padding(.vertical, LocktySpacing.md)
            .overlay {
                Capsule(style: .continuous)
                    .stroke(LocktyColors.cardStroke, lineWidth: 1)
            }
    }

    /// What state the routine is in, in the fewest words that are still true.
    private var subtitleLine: String {
        if activeSince != nil {
            return "Schedule · Running now"
        }
        guard let nextStart else { return "Schedule" }
        return "Schedule · \(startsInText(nextStart))"
    }

    private func startsInText(_ date: Date) -> String {
        let seconds = max(date.timeIntervalSinceNow, 0)
        let days = Int(seconds / 86_400)
        if days >= 1 {
            return days == 1 ? "Starts in 1 day" : "Starts in \(days) days"
        }

        let hours = Int(seconds / 3_600)
        if hours >= 1 {
            return hours == 1 ? "Starts in 1 hour" : "Starts in \(hours) hours"
        }

        let minutes = max(Int(seconds / 60), 1)
        return minutes == 1 ? "Starts in 1 minute" : "Starts in \(minutes) minutes"
    }

    // MARK: - Rows

    private var summaryCard: some View {
        VStack(spacing: 0) {
            row("During these hours") {
                Text(scheduleText)
                    .monospacedDigit()
            }

            divider

            row("On these days") {
                Text(daysText)
            }

            divider

            row("Block") {
                HStack(spacing: LocktySpacing.sm) {
                    if !applicationTokens.isEmpty {
                        LocktyStackedAppTokens(tokens: applicationTokens)
                    }
                    Text(blockedText)
                }
            }

            divider

            // The friction is the whole answer to "how hard is it to get out of this",
            // so it belongs beside the schedule rather than only inside the editor.
            row("Friction") {
                Text(frictionText)
            }

            divider

            row("Unlocks allowed") {
                Text(viewModel.breaksAllowed ? "Yes" : "No")
            }
        }
        .padding(.horizontal, LocktySpacing.md)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white.opacity(0.055))
        )
        .locktyImperfectBorder(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func row<Value: View>(
        _ title: String,
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

    // MARK: - Values

    private var scheduleText: String {
        let schedule = viewModel.scheduleTrigger
        return String(
            format: "%02d:%02d – %02d:%02d",
            schedule.hour, schedule.minute, schedule.endHour, schedule.endMinute
        )
    }

    private var daysText: String {
        RoutineEditorView.previewPresetName(for: viewModel.scheduleTrigger.weekdays)
    }

    private var blockedText: String {
        let count = viewModel.selectionPreview.applicationTokens.count
        let categories = viewModel.selectionPreview.categoryTokens.count

        if count == 0 && categories > 0 {
            return categories == 1 ? "1 Category" : "\(categories) Categories"
        }
        return count == 1 ? "1 App" : "\(count) Apps"
    }

    private var frictionText: String {
        viewModel.selectedPauseFlow?.name ?? "None"
    }
}
