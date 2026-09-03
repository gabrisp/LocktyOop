import SwiftUI

/// A figure, a verdict, and a bar that says where the figure sits.
///
/// A number on its own is not a reading. "40 unlocks" means nothing until you know
/// whether forty is a lot -- and the honest answer to that is not a target somebody
/// invented, it is your own usual. The bar has your usual in the middle, fills to the
/// right when the day is worse than it and to the left when it is better, and the word on
/// the end says which in one glance.
///
/// The two halves are coloured in opposite directions on purpose. Filling rightwards in
/// red and leftwards in green means the bar is read the same way whichever figure it is
/// carrying, without anyone having to remember whether more is good this time.
struct LocktyGaugeRow: View {
    let title: String
    /// What the figure says. A count, a duration -- whatever it is, already formatted.
    let value: String
    /// Where it sits against the usual: 0 is far better than usual, 0.5 is usual, 1 is
    /// far worse. Nil when there is no history to place it against, which draws the
    /// track and no fill rather than guessing at the middle.
    let position: Double?
    /// What sits at the centre of the track. Usually the word for an ordinary day.
    var anchorLabel: String = "USUAL"
    /// Whether a higher figure is the worse one. Screen time yes, time away no.
    var higherIsWorse = true

    private var verdict: (text: String, color: Color)? {
        guard let position else { return nil }

        // Three bands, not a gradient of adjectives: the middle third is an ordinary day
        // and should be told it is ordinary rather than given a grade.
        switch position {
        case ..<0.34: return ("Great", LocktyColors.productive)
        case ..<0.67: return ("Usual", LocktyColors.secondaryText)
        default: return (higherIsWorse ? "Slow down" : "Room to grow", LocktyColors.unproductive)
        }
    }

    private var fillColor: Color {
        guard let position else { return LocktyColors.neutral }
        return position < 0.5 ? LocktyColors.productive : LocktyColors.unproductive
    }

    var body: some View {
        // The heading and its bar are two readings of one figure, not a label sitting on
        // a control -- so they want air between them. Tight, the "USUAL" marker crowds
        // the words above it and the pair reads as one squashed row.
        VStack(alignment: .leading, spacing: LocktySpacing.lg) {
            HStack(alignment: .firstTextBaseline, spacing: LocktySpacing.sm) {
                Text(title)
                    .font(.system(.headline, design: .default, weight: .semibold))
                    .foregroundStyle(LocktyColors.primaryText)

                Text(value)
                    .font(.system(.headline, design: .default, weight: .semibold))
                    .foregroundStyle(LocktyColors.tertiaryText)
                    .monospacedDigit()
                    .contentTransition(.numericText())

                Spacer(minLength: LocktySpacing.sm)

                if let verdict {
                    Text(verdict.text)
                        .font(.system(.headline, design: .default, weight: .semibold))
                        .foregroundStyle(verdict.color)
                        .lineLimit(1)
                }
            }

            track
        }
        .animation(.smooth(duration: 0.6), value: position)
    }

    private var track: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let centre = width / 2
            let ratio = CGFloat(position ?? 0.5)
            let end = width * ratio

            ZStack(alignment: .leading) {
                // The empty track, with ticks. The ticks are what make a half-full bar
                // read as a scale rather than as a progress bar that stopped.
                Capsule()
                    .fill(LocktyColors.ink(0.07))
                    .frame(height: 6)

                HStack(spacing: 0) {
                    ForEach(1..<8, id: \.self) { _ in
                        Rectangle()
                            .fill(LocktyColors.ink(0.10))
                            .frame(width: 1, height: 6)

                        Spacer(minLength: 0)
                    }
                }
                .frame(width: width, height: 6)

                if position != nil {
                    // From the middle outwards, which is the whole idea: the bar grows
                    // away from an ordinary day in whichever direction the day went.
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [fillColor.opacity(0.15), fillColor],
                                startPoint: ratio < 0.5 ? .trailing : .leading,
                                endPoint: ratio < 0.5 ? .leading : .trailing
                            )
                        )
                        .frame(width: abs(end - centre), height: 6)
                        .offset(x: min(end, centre))
                }

                anchor
                    .position(x: centre, y: 3)
            }
            .frame(height: 6)
        }
        .frame(height: 34)
    }

    /// The marker at the middle. Sits on the track rather than beside it, because what it
    /// marks is the point the fill grows from.
    private var anchor: some View {
        Text(anchorLabel)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(LocktyColors.primaryText)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background {
                Capsule(style: .continuous)
                    .fill(LocktyColors.background)
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(LocktyColors.ink(0.14), lineWidth: 1.5)
                    }
            }
    }
}
