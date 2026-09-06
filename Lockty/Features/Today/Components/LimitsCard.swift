import SwiftUI

/// What the limits have left today.
///
/// Above the scheduled routines and below the day itself, which is the order the three
/// answer in: what happened, what is being held right now, what starts later.
struct LimitsCard: View {
    let limits: [TodayLimitState]
    var onSelect: ((UUID) -> Void)?
    var onOpenSection: (() -> Void)?

    var body: some View {
        // The same inset the Screen Time card above it uses. Two cards in the same
        // column at two different paddings read as two different kinds of object.
        CardView(radius: LocktyRadius.medium, padding: LocktySpacing.xl) {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    onOpenSection?()
                } label: {
                    LocktySectionTitle("Limits", showsChevron: true)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.bottom, LocktySpacing.md)

                ForEach(Array(limits.enumerated()), id: \.element.id) { index, limit in
                    if index > 0 {
                        // Between rules, with room on both sides: each block is a rule's
                        // name, its total and the apps under it, and a hairline pressed
                        // against the last app made two rules read as one list.
                        Divider()
                            .overlay(LocktyColors.separator.opacity(0.45))
                            .padding(.vertical, LocktySpacing.md)
                    }

                    Button {
                        onSelect?(limit.id)
                    } label: {
                        row(limit)
                    }
                    // Lights its own contents rather than laying a shape over them: a
                    // rounded rectangle drawn on press inside a card is a card inside a
                    // card, and these rows have no edge of their own to light.
                    .buttonStyle(.locktyInteractive(brighten: true))
                    .tappable()
                }
            }
        }
    }

    private func row(_ limit: TodayLimitState) -> some View {
        VStack(alignment: .leading, spacing: LocktySpacing.sm) {
            heading(limit)

            // What each app spent of the shared allowance -- but only when there is a
            // share to divide. A daily limit over three apps is one budget between them,
            // and the total never says which of the three is spending it; over one app the
            // split *is* the total, so the line under "37m of 2h" was the same 37 minutes
            // written a second time with the app's name in front of it.
            if limit.apps.count > 1 {
                VStack(spacing: 4) {
                    ForEach(limit.apps) { app in
                        HStack(spacing: LocktySpacing.sm) {
                            Text(app.name)
                                .font(.system(.footnote, design: .default, weight: .regular))
                                .foregroundStyle(LocktyColors.secondaryText)
                                .lineLimit(1)

                            Spacer(minLength: LocktySpacing.sm)

                            Text(app.detail)
                                .font(.system(.footnote, design: .default, weight: .regular))
                                .foregroundStyle(LocktyColors.tertiaryText)
                                .monospacedDigit()
                                .contentTransition(.numericText())
                        }
                    }
                }
                .padding(.leading, 46)
            }
        }
        .contentShape(Rectangle())
    }

    private func heading(_ limit: TodayLimitState) -> some View {
        HStack(spacing: LocktySpacing.md) {
            // The icons, not a glyph standing in for them. A limit is about particular
            // apps and this is the fastest way to say which.
            if !limit.tokens.isEmpty {
                LocktyStackedAppTokens(tokens: limit.tokens)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Text(limit.name)
                        .font(.system(.subheadline, design: .default, weight: .semibold))
                        .foregroundStyle(LocktyColors.primaryText)
                        .lineLimit(1)

                    // A padlock on the kinds the shield meters. Those apps are shut right
                    // now whatever the count says, and the count is how many times you
                    // may come through -- without this the row reads as a budget with
                    // everything still in it over an app that will not open.
                    if limit.isHeldShut {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(LocktyColors.tertiaryText)
                    }
                }

                Text(limit.detail)
                    .font(.system(.footnote, design: .default, weight: .regular))
                    .foregroundStyle(limit.isSpent ? LocktyColors.unproductive : LocktyColors.secondaryText)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)

                if let fraction = limit.fraction {
                    bar(fraction: fraction, tint: tint(for: fraction, isSpent: limit.isSpent))
                }
            }

            Spacer(minLength: 0)
        }
        .frame(minHeight: 58)
    }

    /// Green while there is room, amber as it runs out, red once it is gone. The same
    /// three bands everything else in the app is judged by.
    private func tint(for fraction: Double, isSpent: Bool) -> Color {
        if isSpent { return LocktyColors.unproductive }
        switch fraction {
        case ..<0.6: return LocktyColors.productive
        case ..<0.85: return LocktyColors.warning
        default: return LocktyColors.unproductive
        }
    }

    /// The same bar the rest of the app draws: solid where it starts, dissolving where it
    /// ends, because a budget spelled in minutes is not precise to the minute.
    private func bar(fraction: Double, tint: Color) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LocktyColors.ink(0.08))
                    .frame(height: 4)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [tint, tint.opacity(0.85), tint.opacity(0.25), tint.opacity(0)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(proxy.size.width * fraction, 6), height: 4)
                    .blur(radius: 1.2)
            }
            .frame(height: 4)
        }
        .frame(height: 4)
        .animation(.smooth(duration: 0.5), value: fraction)
    }
}
