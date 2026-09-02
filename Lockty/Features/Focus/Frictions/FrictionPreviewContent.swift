import SwiftUI

/// A friction at rest: what it will ask of you, in order, with nothing to fill in.
///
/// The sibling of `RoutinePreviewContent`, and for the same reason: opening a friction
/// used to drop you straight into its form, so reading one meant reading a page of
/// controls. A friction is a sequence, and a sequence is best read as a list of what
/// happens rather than as the fields that produced it.
struct FrictionPreviewContent: View {
    var onEdit: (() -> Void)?
    @ObservedObject var viewModel: FrictionEditorViewModel

    private var steps: [FrictionStep] {
        viewModel.draft.steps
    }

    var body: some View {
        VStack(spacing: LocktySpacing.lg) {
            badge

            VStack(spacing: 2) {
                Text(subtitleLine)
                    .font(.system(.subheadline, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.secondaryText)
                    .lineLimit(1)

                Text(viewModel.draft.name)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(LocktyColors.primaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }

            sequenceCard

            settingsCard
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, LocktySpacing.screenInset)
        .padding(.top, LocktySpacing.sm)
        .padding(.bottom, LocktySpacing.md)
    }

    /// The friction's own glyph, which is its first step's -- the same one its card in
    /// Focus shows, so the two are recognisably the same object.
    private var badge: some View {
        Image(systemName: steps.lazy.compactMap(\.symbolName).first ?? "slider.horizontal.3")
            .font(.system(size: 24, weight: .regular))
            .foregroundStyle(LocktyColors.primaryText)
            .padding(.horizontal, LocktySpacing.xl)
            .padding(.vertical, LocktySpacing.md)
            .overlay {
                Capsule(style: .continuous)
                    .stroke(LocktyColors.cardStroke, lineWidth: 1)
            }
    }

    private var subtitleLine: String {
        let count = steps.count
        let stepText = count == 1 ? "1 step" : "\(count) steps"
        return "Friction · \(stepText)"
    }

    /// What the flow asks, in the order it asks. Numbered, because the order is the
    /// substance of a friction -- a countdown before a puzzle is a different thing from
    /// a puzzle before a countdown.
    private var sequenceCard: some View {
        VStack(spacing: 0) {
            row(
                leading: "1",
                title: "Breathe",
                value: LocktyBreathe.label(viewModel.draft.breatheSeconds)
            )

            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                divider

                row(
                    leading: "\(index + 2)",
                    title: step.title,
                    value: step.detail
                )
            }
        }
        .padding(.horizontal, LocktySpacing.cardInset)
        .locktyCardBackground(cornerRadius: 26)
    }

    /// What happens once the flow is answered, which is not part of the sequence and so
    /// is not numbered with it.
    private var settingsCard: some View {
        VStack(spacing: 0) {
            row(
                title: "Unlocks for",
                value: viewModel.draft.allowanceMinutes == 1
                    ? "1 minute"
                    : "\(viewModel.draft.allowanceMinutes) minutes"
            )

            divider

            row(
                title: "Relocks after",
                value: viewModel.draft.relockAfterAllowance ? "Yes" : "No"
            )
        }
        .padding(.horizontal, LocktySpacing.cardInset)
        .locktyCardBackground(cornerRadius: 26)
    }

    private func row(leading: String? = nil, title: String, value: String) -> some View {
        HStack(spacing: LocktySpacing.md) {
            if let leading {
                Text(leading)
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(LocktyColors.secondaryText)
                    .monospacedDigit()
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(LocktyColors.ink(0.08)))
            }

            Text(title)
                .font(.system(.body, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.primaryText)

            Spacer(minLength: LocktySpacing.sm)

            Text(value)
                .font(.system(.body, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.secondaryText)
                .lineLimit(1)
        }
        .frame(minHeight: 56)
        .locktyEditOnLongPress(onEdit)
    }

    private var divider: some View {
        Divider()
            .overlay(LocktyColors.separator.opacity(0.45))
    }
}
