import SwiftUI

/// What your rules did today.
///
/// The Screen Time card's shape, like the objectives card beside it: a figure, a rule
/// under it, and a few rows of what went into it. The whole card is one button to the
/// rules screen -- not the heading alone, which leaves most of a card looking pressable
/// and doing nothing.
///
/// Separate from the limits card, which answers a different question: that one is about
/// what is left of a budget right now, and this is about what ran.
struct RulesCard: View {
    let stats: [RuleStat]
    var onOpen: (() -> Void)?

    private let maximumShown = 4

    private var ran: [RuleStat] {
        stats.filter { $0.runs > 0 || $0.isRunning }
    }

    private var shown: [RuleStat] {
        // Running first, then whatever ran most: what is on right now is the reason to
        // look at this.
        Array(ran.sorted { left, right in
            if left.isRunning != right.isRunning { return left.isRunning }
            return left.runs > right.runs
        }.prefix(maximumShown))
    }

    var body: some View {
        Button {
            onOpen?()
        } label: {
            CardView(radius: LocktyRadius.medium, padding: LocktySpacing.xl, interactive: true) {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    if ran.isEmpty {
                        Text("Nothing has run today. A schedule starts on its own; a limit waits until something has had its share.")
                            .font(.system(.footnote, design: .default, weight: .regular))
                            .foregroundStyle(LocktyColors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, LocktySpacing.md)
                    } else {
                        Divider()
                            .overlay(LocktyColors.ink(0.12))
                            .padding(.top, 18)
                            .padding(.bottom, 26)

                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(shown) { stat in
                                row(stat)
                            }
                        }
                        // A picture of the day, not controls: the card is one button, and
                        // anything inside it that takes a tap takes it from the card.
                        .allowsHitTesting(false)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.locktyInteractive)
        .tappable()
        // No gesture of its own. Holding a card already does something: `CardView`'s
        // interactive surface grows it and washes its tint over while the finger is down,
        // which is what every other card on this screen does and all this one was missing.
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            LocktySectionTitle("Rules", showsChevron: true)

            HStack(alignment: .firstTextBaseline, spacing: LocktySpacing.sm) {
                Text("\(ran.count)")
                    .font(.system(.largeTitle, design: .default, weight: .semibold))
                    .foregroundStyle(LocktyColors.primaryText)
                    .monospacedDigit()
                    .locktyNumericTransition(trigger: ran.count)
                    .blur(radius: 1.2)
                    .lineLimit(1)

                Text(ran.count == 1 ? "ran today" : "run today")
                    .font(.system(.subheadline, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.secondaryText)

                Spacer(minLength: 0)
            }
            .padding(.top, 4)
        }
    }

    private func row(_ stat: RuleStat) -> some View {
        HStack(spacing: LocktySpacing.md) {
            Image(systemName: stat.symbolName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(stat.tint)
                .frame(width: 38, height: 38)
                .background { Circle().fill(stat.tint.opacity(0.14)) }

            VStack(alignment: .leading, spacing: 2) {
                Text(stat.name)
                    .font(.system(.subheadline, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.primaryText)
                    .lineLimit(1)

                Text(stat.detail)
                    .font(.system(.footnote, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.tertiaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if stat.isRunning {
                Text("On")
                    .font(.system(.footnote, design: .default, weight: .semibold))
                    .foregroundStyle(stat.tint)
                    .padding(.horizontal, LocktySpacing.md)
                    .frame(height: 26)
                    .background {
                        Capsule(style: .continuous)
                            .fill(stat.tint.opacity(0.14))
                    }
            }
        }
    }
}
