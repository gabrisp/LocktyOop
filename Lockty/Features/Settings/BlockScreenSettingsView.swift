import SwiftUI

/// What the shield says when it stops you.
///
/// A list of packs with a switch each, several of which can be on at once: one pack read
/// twenty times becomes wallpaper, and the point of a message on a block screen is that
/// it is still being read on the twentieth day. When more than one is on, the shield
/// picks a pack at random and then a line from inside it.
///
/// Two of the packs are not lists at all -- what this app has cost today, and the reason
/// you wrote for yourself. They sit in the same list because from here they are the same
/// question: what should this screen say?
struct BlockScreenSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @FocusState private var isIntentionFocused: Bool

    private var preferences: ShieldScreenPreferences { viewModel.shieldScreen }

    var body: some View {
        LocktySectionScreen(title: "Block screens") {
            Text("Turn on as many as you like. The shield picks one each time, so it stays worth reading.")
                .font(.system(.subheadline, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                ForEach(Array(ShieldScreenCatalog.packs.enumerated()), id: \.element.id) { index, pack in
                    if index > 0 {
                        Divider().overlay(LocktyColors.separator.opacity(0.45))
                    }

                    packRow(pack)
                }
            }
            .padding(.horizontal, LocktySpacing.cardInset)
            .locktyCardBackground(cornerRadius: 26)

            // Only where it is used. A field asking for a reason under a pack that will
            // not show it is a question with no consequence.
            if preferences.resolvedPackIDs.contains("intention") {
                intentionField
            }

            Text("Quiet turns the others off: \u{201C}say nothing\u{201D} and \u{201C}say this\u{201D} cannot both be true.")
                .font(.system(.footnote, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .animation(.smooth(duration: 0.28), value: preferences.enabledPackIDs)
        .task { viewModel.refresh() }
    }

    private var intentionField: some View {
        VStack(alignment: .leading, spacing: LocktySpacing.sm) {
            Text("Your reason")
                .font(.system(.headline, design: .default, weight: .semibold))
                .foregroundStyle(LocktyColors.primaryText)

            TextField(
                "Because mornings are for writing.",
                text: Binding(
                    get: { preferences.intention },
                    set: { viewModel.setShieldIntention($0) }
                ),
                axis: .vertical
            )
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

    private func packRow(_ pack: ShieldScreenPack) -> some View {
        HStack(alignment: .top, spacing: LocktySpacing.md) {
            // The emoji is the pack's face. A symbol set would flatten twelve very
            // different voices into one grey glyph vocabulary.
            Text(pack.emoji)
                .font(.system(size: 22))
                .frame(width: 30)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: LocktySpacing.sm) {
                    Text(pack.title)
                        .font(.system(.subheadline, design: .default, weight: .semibold))
                        .foregroundStyle(LocktyColors.primaryText)

                    if pack.isPro {
                        proBadge
                    }
                }

                Text(pack.subtitle)
                    .font(.system(.footnote, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)

                // A line from the pack itself, so the choice is made by reading one
                // rather than by reading a description of one.
                if let sample = pack.messages.first {
                    Text(sample.replacingOccurrences(of: "\n", with: " "))
                        .font(.system(.footnote, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.tertiaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 1)
                }
            }

            Spacer(minLength: LocktySpacing.sm)

            LocktySwitch(
                isOn: Binding(
                    get: { preferences.isEnabled(pack) },
                    set: { _ in viewModel.toggleShieldPack(pack) }
                )
            )
            .padding(.top, 2)
        }
        .padding(.vertical, LocktySpacing.md)
        .frame(minHeight: 64)
    }

    private var proBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "bolt.fill")
            Text("PRO")
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(LocktyColors.productive)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .overlay {
            Capsule(style: .continuous)
                .stroke(LocktyColors.productive.opacity(0.55), lineWidth: 1)
        }
    }
}
