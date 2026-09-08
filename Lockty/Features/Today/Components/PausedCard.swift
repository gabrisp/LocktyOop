import SwiftUI

/// What is on hold, and how to let it go again.
///
/// A paused rule is not shown among the limits and a paused routine is not shown among
/// the scheduled ones -- neither is going to do anything, and listing them there would be
/// the screen promising something that will not happen. But they cannot simply vanish
/// either: a rule that disappeared when it was held would look deleted, and the only way
/// back to it would be remembering it existed.
///
/// So they gather here, each with the day the hold ends and a way to end it early. Held
/// rather than tapped, like every other decision that changes what the phone does to you:
/// a limit is easy to hold and should not be easy to drop by brushing the screen.
struct PausedCard: View {
    let items: [TodayPausedItem]
    var onResume: ((UUID) -> Void)?

    var body: some View {
        CardView(radius: LocktyRadius.medium, padding: LocktySpacing.xl) {
            VStack(alignment: .leading, spacing: 0) {
                // The heading every other card on Today wears, not the small eyebrow with
                // a rule above it. `Scheduled` and this one are siblings -- two lists of
                // routines, one running later and one not running on purpose -- and they
                // were titled in two different styles. No chevron: unlike `Scheduled`,
                // a hold has no screen of its own to open.
                LocktySectionTitle("On hold", showsChevron: false)
                    .padding(.bottom, LocktySpacing.md)

                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Divider()
                            .overlay(LocktyColors.separator.opacity(0.45))
                            .padding(.vertical, LocktySpacing.md)
                    }

                    row(item)
                }
            }
        }
    }

    private func row(_ item: TodayPausedItem) -> some View {
        VStack(alignment: .leading, spacing: LocktySpacing.md) {
            HStack(spacing: LocktySpacing.md) {
                Image(systemName: item.symbolName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(LocktyColors.secondaryText)
                    .frame(width: 34, height: 34)
                    .background { Circle().fill(LocktyColors.ink(0.06)) }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(.subheadline, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.primaryText)
                        .lineLimit(1)

                    Text(item.detail)
                        .font(.system(.footnote, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.tertiaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            LocktyHoldButton(
                title: "Hold to resume",
                systemImage: "play.fill",
                tint: LocktyColors.productive
            ) {
                onResume?(item.id)
            }
        }
    }
}
