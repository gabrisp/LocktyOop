import SwiftUI

/// Control, Detox and Productivity, as three circles whose rim is the score.
///
/// The rim is drawn, not blurred. An aura says roughly how it is going; a stroke that
/// stops at 71% of the way round says the number without repeating it, and the two
/// together -- a hard edge with its own glow behind it -- is the one place in the app
/// where a value is a shape rather than a colour.
///
/// No background and no pinning. They sit in the scroll like any other row.
struct DailyScoreRocksView: View {
    let metrics: [PrimaryMetric]
    var onSelect: ((PrimaryMetricKind) -> Void)?

    var body: some View {
        HStack(spacing: LocktySpacing.sm) {
            ForEach(metrics) { metric in
                pill(metric)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// How wide each one is. A circle, not a capsule: the number is one or two digits
    /// and a pill around it is mostly empty pill -- and a ring is what a value going
    /// round an edge wants to be drawn on.
    @Environment(\.colorScheme) private var colorScheme

    private let side: CGFloat = 100

    private func pill(_ metric: PrimaryMetric) -> some View {
        Button {
            onSelect?(metric.kind)
        } label: {
            VStack(spacing: LocktySpacing.sm) {
                // No glyph. The label under it already names the score, and a symbol
                // beside the number in a circle this size leaves neither room to be read.
                ZStack {
                    bloom(metric)
                    face(metric)
                    value(metric)
                }
                .frame(width: side, height: side)
                .compositingGroup()
                // The press surface in the circle's own outline, inside the label where
                // the style publishes the pressed state. The style scales and lights the
                // whole cell; this is what makes the light land *on the circle* rather
                // than on the label under it as well.
                .locktyInteractiveSurface(shape: Circle(), pressedScale: 0.95)

                Text(metric.kind.title)
                    .font(.system(.footnote, design: .default, weight: .semibold))
                    .foregroundStyle(LocktyColors.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
        // Lights its own contents rather than laying a shape over them: the circle
        // already has an edge, and a second one drawn on press is a ring around a ring.
        .buttonStyle(.locktyInteractive(brighten: true))
        .tappable()
    }

    /// Outside the circle: a blurred copy of it in the metric's colour, so the light
    /// comes off the shape rather than sitting behind it as a square of colour.
    private func bloom(_ metric: PrimaryMetric) -> some View {
        Circle()
            .fill(tint(metric))
            .frame(width: side * 0.92, height: side * 0.92)
            .blur(radius: 18)
            .opacity(0.7)
            .locktyGlow(lightScale: 0.6)
            .animation(.smooth(duration: 0.6), value: metric.value)
    }

    /// The circle's body: nearly the ground it sits on, lifted a little in the middle and
    /// pressed in at the rim.
    ///
    /// The inner shadow is what turns a flat disc into something with a body -- a wide
    /// stroke of the screen's own background, blurred and clipped inside the shape, so
    /// the edges go darker than the centre. The same three layers the rock has, at a
    /// tenth of the size.
    private func face(_ metric: PrimaryMetric) -> some View {
        Circle()
            .fill(tint(metric).opacity(0.14))
            .background { Circle().fill(LocktyColors.background) }
            .overlay {
                RadialGradient(
                    colors: [tint(metric).opacity(0.20), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: side * 0.42
                )
                .locktyGlow(lightScale: 0.7)
                .mask { Circle() }
            }
            .overlay {
                Circle()
                    .stroke(LocktyColors.background, lineWidth: 14)
                    .blur(radius: 8)
                    .mask { Circle() }
            }
            .overlay { rim(metric) }
            .animation(.smooth(duration: 0.6), value: metric.value)
    }

    private func value(_ metric: PrimaryMetric) -> some View {
        let text = Text(metric.displayValue.replacingOccurrences(of: "%", with: ""))
            .font(.system(size: 26, weight: .bold))
            .monospacedDigit()
            .contentTransition(.numericText())

        return text
            .foregroundStyle(colorScheme == .dark ? .white : LocktyColors.deep(tint(metric)))
            .background {
                text
                    .foregroundStyle(tint(metric))
                    .blur(radius: 7)
                    .locktyGlow(lightScale: 0.85)
                    .opacity(colorScheme == .dark ? 1 : 0)
            }
            .animation(.smooth(duration: 0.9), value: metric.value)
    }

    private func tint(_ metric: PrimaryMetric) -> Color {
        switch metric.tone {
        case .weak: LocktyColors.unproductive
        case .balanced: LocktyColors.warning
        case .strong: LocktyColors.productive
        }
    }

    /// The track, then the part of it that has been earned, then that same arc again
    /// blurred behind itself.
    ///
    /// The glow is a second copy rather than a shadow: a shadow follows the shape's
    /// whole outline, and what should be glowing is the arc, not the pill.
    private func rim(_ metric: PrimaryMetric) -> some View {
        let progress = max(min(metric.progress, 1), 0.02)

        return ZStack {
            Circle()
                .stroke(LocktyColors.ink(0.10), lineWidth: 2.5)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint(metric), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .blur(radius: 5)
                .locktyGlow(lightScale: 0.7)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint(metric), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
        // From the top, clockwise. A circle's path starts at three o'clock, which would
        // have every score beginning on its right-hand side for no reason anyone could
        // see -- unlike a capsule, a circle has no top edge of its own to start from.
        .rotationEffect(.degrees(-90))
        .animation(.smooth(duration: 0.9), value: metric.value)
    }
}
