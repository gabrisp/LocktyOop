import SwiftUI

/// What the shield says when it stops you.
///
/// One choice, not a shop. The shield is the only part of Lockty most people see on a bad
/// day, and the interesting question is what is worth saying at that moment -- what it
/// costs, what you meant to do instead, or nothing -- rather than which celebrity says it.
struct BlockScreenSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @FocusState private var isIntentionFocused: Bool

    var body: some View {
        LocktySectionScreen(title: "Block screens") {
            Text("Every style still says which routine is running and how to get past it. They differ in what they add.")
                .font(.system(.subheadline, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                ForEach(Array(ShieldScreenStyle.allCases.enumerated()), id: \.element) { index, style in
                    if index > 0 {
                        Divider().overlay(LocktyColors.separator.opacity(0.45))
                    }

                    styleRow(style)
                }
            }
            .padding(.horizontal, LocktySpacing.cardInset)
            .locktyCardBackground(cornerRadius: 26)

            // Only where it is used. A field asking for a reason under a style that will
            // not show it is a question with no consequence.
            if viewModel.shieldScreen.style == .intention {
                VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                    Text("Your reason")
                        .font(.system(.headline, design: .default, weight: .semibold))
                        .foregroundStyle(LocktyColors.primaryText)

                    TextField("Because mornings are for writing.", text: intentionBinding, axis: .vertical)
                        .focused($isIntentionFocused)
                        .lineLimit(2...4)
                        .font(.system(.body, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.primaryText)
                        .padding(.horizontal, LocktySpacing.cardInset)
                        .padding(.vertical, LocktySpacing.md)
                        .locktyCardBackground(cornerRadius: 22)
                }
                .transition(.blurReplace.combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.28), value: viewModel.shieldScreen.style)
        .task { viewModel.refresh() }
    }

    private var intentionBinding: Binding<String> {
        Binding(
            get: { viewModel.shieldScreen.intention },
            set: { viewModel.setShieldIntention($0) }
        )
    }

    private func styleRow(_ style: ShieldScreenStyle) -> some View {
        Button {
            viewModel.setShieldStyle(style)
        } label: {
            HStack(spacing: LocktySpacing.md) {
                Image(systemName: style.systemImage)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(LocktyColors.primaryText)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text(style.title)
                        .font(.system(.subheadline, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.primaryText)

                    Text(style.subtitle)
                        .font(.system(.footnote, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: LocktySpacing.sm)

                // One choice, so a tick rather than a switch: four switches would let you
                // turn all of them off, and a shield with no style is not a thing.
                Image(systemName: viewModel.shieldScreen.style == style ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(
                        viewModel.shieldScreen.style == style
                        ? LocktyColors.productive
                        : LocktyColors.secondaryText
                    )
            }
            .padding(.vertical, LocktySpacing.md)
            .frame(minHeight: 58)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.locktyInteractive(shape: RoundedRectangle(cornerRadius: 14, style: .continuous)))
        .tappable()
    }
}
