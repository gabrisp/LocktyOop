import SwiftUI

/// Focus, Held and Checks, as three compact pills whose rim is the score.
///
/// The rim is drawn, not blurred. An aura says roughly how it is going; a stroke that
/// stops at 71% of the way round says the number without repeating it, and the two
/// together -- a hard edge with its own glow behind it -- is the one place in the app
/// where a value is a shape rather than a colour.
///
/// No background and no pinning. They sit in the scroll like any other row.
struct DailyScoreRocksView: View {
    let metrics: [PrimaryMetric]
    /// Which one is being read, on a screen that is reading one.
    ///
    /// The others go behind a blur: the page is about one of them and the other two are
    /// the comparison, so a number you can half-see is an invitation to look properly.
    /// They stay tappable at full size -- a target you can see but not hit is worse than
    /// one you cannot see at all. Nil means none is singled out, which is Today.
    var focusedKind: PrimaryMetricKind?
    var onSelect: ((PrimaryMetricKind) -> Void)?

    var body: some View {
        // Centred, and each one only as wide as its own number. Stretched to equal
        // thirds they read as a segmented control -- three parts of one thing, where
        // these are three separate answers that happen to sit together.
        HStack(spacing: LocktySpacing.xl) {
            ForEach(metrics) { metric in
                let isDimmed = focusedKind != nil && metric.kind != focusedKind

                pill(metric)
                    .blur(radius: isDimmed ? 3.5 : 0)
                    .opacity(isDimmed ? 0.55 : 1)
                    .scaleEffect(isDimmed ? 0.9 : 1)
                    .animation(.smooth(duration: 0.38), value: focusedKind)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @Environment(\.colorScheme) private var colorScheme

    /// How tall each pill is. The width comes from the number inside it, so a "7" is a
    /// narrow pill and a "100" a wider one -- the shape is the figure's own, not a slot
    /// it has been dropped into.
    private let height: CGFloat = 48

    private func pill(_ metric: PrimaryMetric) -> some View {
        Button {
            onSelect?(metric.kind)
        } label: {
            VStack(spacing: 6) {
                // No glyph. The label under it already names the score, and a symbol
                // beside the number leaves neither room to be read.
                ZStack {
                    bloom(metric)
                    face(metric)

                    HStack(spacing: 5) {
                        // Small, and before the number: it says which of the three this
                        // is at a glance, where the word underneath says it properly.
                        Image(systemName: metric.kind.systemImage)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(tint(metric))

                        value(metric)
                    }
                    .padding(.horizontal, LocktySpacing.lg)
                }
                .frame(height: height)
                .fixedSize(horizontal: true, vertical: false)
                .compositingGroup()
                // The press surface in the pill's own outline, inside the label where the
                // style publishes the pressed state -- so the light lands on the pill
                // rather than on the word beneath it as well.
                .locktyInteractiveSurface(shape: Capsule(style: .continuous), pressedScale: 0.95)

                Text(metric.kind.title)
                    .font(.system(.footnote, design: .default, weight: .semibold))
                    .foregroundStyle(LocktyColors.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        // Lights its own contents rather than laying a shape over them: the circle
        // already has an edge, and a second one drawn on press is a ring around a ring.
        .buttonStyle(.locktyInteractive(brighten: true))
        .tappable()
    }

    /// Outside the circle: a blurred copy of it in the metric's colour, so the light
    /// comes off the shape rather than sitting behind it as a square of colour.
    private func bloom(_ metric: PrimaryMetric) -> some View {
        Capsule(style: .continuous)
            .fill(tint(metric))
            .blur(radius: 14)
            .opacity(0.65)
            .locktyGlow(lightScale: 0.6)
            .padding(-2)
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
        let shape = Capsule(style: .continuous)
        let colour = tint(metric)
        let wash = RadialGradient(
            colors: [colour.opacity(0.20), Color.clear],
            center: .center,
            startRadius: 0,
            endRadius: height * 0.7
        )

        return shape
            .fill(colour.opacity(0.14))
            .background { shape.fill(LocktyColors.background) }
            .overlay { wash.locktyGlow(lightScale: 0.7).mask { shape } }
            .overlay { innerShadow(shape) }
            .overlay { rim(metric) }
            .animation(.smooth(duration: 0.6), value: metric.value)
    }

    /// The ground pressed in from the rim, which is what turns a flat capsule into
    /// something with a body.
    private func innerShadow(_ shape: Capsule) -> some View {
        shape
            .stroke(LocktyColors.background, lineWidth: 10)
            .blur(radius: 6)
            .mask { shape }
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
            Capsule(style: .continuous)
                .stroke(LocktyColors.ink(0.10), lineWidth: 2)

            Capsule(style: .continuous)
                .trim(from: 0, to: progress)
                .stroke(tint(metric), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .blur(radius: 4)
                .locktyGlow(lightScale: 0.7)

            Capsule(style: .continuous)
                .trim(from: 0, to: progress)
                .stroke(tint(metric), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        // No rotation. A capsule's path already begins at the top of its own straight
        // edge; turning it would turn the shape, not the starting point.
        .animation(.smooth(duration: 0.9), value: metric.value)
    }
}
