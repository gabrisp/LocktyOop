import SwiftUI

/// Which friction a quick timer asks for, or none at all.
///
/// A list rather than the routine editor's card, because a timer has one question to ask
/// here and no form around it. "None" is a row like the others: a timer with no friction
/// is a perfectly ordinary thing to want, and leaving it as the absence of a choice makes
/// it look like a mistake.
struct QuickTimerFrictionPicker: View {
    let frictions: [Friction]
    let selectedID: UUID?
    let onSelect: (Friction?) -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                row(
                    title: "None",
                    subtitle: "Unlocking asks nothing.",
                    isSelected: selectedID == nil
                ) {
                    onSelect(nil)
                }

                ForEach(frictions) { friction in
                    Divider().overlay(LocktyColors.separator.opacity(0.45))

                    row(
                        title: friction.name,
                        subtitle: friction.steps.count == 1 ? "1 step" : "\(friction.steps.count) steps",
                        isSelected: selectedID == friction.id
                    ) {
                        onSelect(friction)
                    }
                }
            }
            .padding(.horizontal, LocktySpacing.cardInset)
            .locktyCardBackground(cornerRadius: 26)
            .padding(.horizontal, LocktySpacing.screenInset)
            .padding(.vertical, LocktySpacing.lg)
        }
        .locktyScreenBackground()
    }

    private func row(
        title: String,
        subtitle: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: LocktySpacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.subheadline, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.primaryText)

                    Text(subtitle)
                        .font(.system(.footnote, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: LocktySpacing.sm)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(isSelected ? LocktyColors.productive : LocktyColors.secondaryText)
            }
            .frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.locktyRow)
        .tappable()
    }
}
