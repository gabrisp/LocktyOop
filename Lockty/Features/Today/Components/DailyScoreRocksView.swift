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
    /// Whether the figures are still on their way.
    ///
    /// The pills stay on screen either way. Three of them appearing once the report
    /// lands is the top of the screen jumping into place every time it is opened -- so
    /// they are here from the first frame, showing nothing, dimmed and softened, and they
    /// fill in where they stand. The component is never taken down and put back up.
    var isPlaceholder = false
    var onSelect: ((PrimaryMetricKind) -> Void)?

    var body: some View {
        // Centred, and each one only as wide as its own number. Stretched to equal
        // thirds they read as a segmented control -- three parts of one thing, where
        // these are three separate answers that happen to sit together.
        HStack(spacing: LocktySpacing.xl) {
            ForEach(metrics) { metric in
                let isDimmed = focusedKind != nil && metric.kind != focusedKind

                pill(metric)
                    // Unknown reads as unlit: no fill on the rim, the ground showing
                    // through, and the number softened into something you can see is a
                    // number without being able to read it as one.
                    .blur(radius: isPlaceholder ? 2.5 : 0)
                    .opacity(isPlaceholder ? 0.45 : 1)
                    .animation(.smooth(duration: 0.45), value: isPlaceholder)
                    // Blur and size, not opacity. Fading a pill out makes it look
                    // switched off; blurring it makes it look behind -- which is what it
                    // is, since it is still there and still tappable. The two animate as
                    // one continuous value, so switching pills is one movement rather
                    // than a cross-fade between two states.
                    .blur(radius: isDimmed ? 4.5 : 0)
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

    /// Outside the circle: a blurred copy of it, so the light comes off the shape rather
    /// than sitting behind it as a square of colour.
    ///
    /// Written twice because a bloom is light, and the two grounds have opposite ideas of
    /// what light is. On black, the metric's colour added on top *is* the glow. On a pale
    /// page there is nothing to add to, so the same layer has to darken instead -- and a
    /// saturated colour multiplied behind the pill comes out as a black ring, which is
    /// what this looked like. What lifts a shape off a grey page is white, so on light it
    /// is white, with the barest wash of the colour over it. The colour has not gone
    /// anywhere: it is in the rim, the glyph and the number.
    @ViewBuilder
    private func bloom(_ metric: PrimaryMetric) -> some View {
        let shape = Capsule(style: .continuous)

        if colorScheme == .dark {
            shape
                .fill(tint(metric))
                .blur(radius: 14)
                .opacity(0.65)
                .blendMode(.plusLighter)
                .padding(-2)
                .animation(.smooth(duration: 0.6), value: metric.value)
        } else {
            ZStack {
                shape
                    .fill(.white)
                    .blur(radius: 12)

                shape
                    .fill(tint(metric))
                    .blur(radius: 16)
                    .opacity(0.18)
            }
            .padding(-2)
            .animation(.smooth(duration: 0.6), value: metric.value)
        }
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
        let isDark = colorScheme == .dark
        let wash = RadialGradient(
            colors: [colour.opacity(isDark ? 0.20 : 0.16), Color.clear],
            center: .center,
            startRadius: 0,
            endRadius: height * 0.7
        )

        return shape
            .fill(colour.opacity(isDark ? 0.14 : 0.10))
            // The ground the pill is cut from. On black that is the page itself; on a
            // pale page it is the card surface, so the pill sits a shade *above* what it
            // is on rather than being invisible against it.
            .background { shape.fill(isDark ? LocktyColors.background : LocktyColors.cardSurface) }
            // The light in the middle of it.
            //
            // Added on black. On white it is simply drawn: multiplying a gradient that
            // ends in `Color.clear` darkens where the colour has run out, and clear is
            // black with no alpha -- which is where the dark halo inside these pills was
            // coming from. It was never the background colour going wrong; it was a blend
            // mode written for a dark screen being asked to light a pale one.
            .overlay {
                wash
                    .blendMode(isDark ? .plusLighter : .normal)
                    .opacity(isDark ? 1 : 0.7)
                    .mask { shape }
            }
            .overlay { innerShadow(shape) }
            .overlay { rim(metric) }
            .animation(.smooth(duration: 0.6), value: metric.value)
    }

    /// The ground pressed in from the rim, which is what turns a flat capsule into
    /// something with a body.
    ///
    /// The page's own colour, whichever page it is: black pressed into a dark pill and
    /// the light grey of the page pressed into a pale one. Both read as the same edge,
    /// because in both cases it is the ground showing through.
    private func innerShadow(_ shape: Capsule) -> some View {
        shape
            .stroke(LocktyColors.background, lineWidth: 10)
            .blur(radius: 6)
            .mask { shape }
    }

    private func value(_ metric: PrimaryMetric) -> some View {
        let text = Text(isPlaceholder ? "00" : metric.displayValue.replacingOccurrences(of: "%", with: ""))
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
        // Nothing earned yet while the figure is unknown: an arc drawn to a value we do
        // not have is a claim, and it would have to be corrected the moment it arrives.
        let progress = isPlaceholder ? 0.02 : max(min(metric.progress, 1), 0.02)

        return ZStack {
            Capsule(style: .continuous)
                .stroke(LocktyColors.ink(0.10), lineWidth: 2)

            // The arc's own halo. Added on black; simply laid down, faintly, on white --
            // multiplying it would draw the same arc in shadow, and a dark line trailing
            // a bright one reads as a smudge rather than as light.
            Capsule(style: .continuous)
                .trim(from: 0, to: progress)
                .stroke(tint(metric), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .blur(radius: 4)
                .opacity(colorScheme == .dark ? 1 : 0.55)
                .blendMode(colorScheme == .dark ? .plusLighter : .normal)

            Capsule(style: .continuous)
                .trim(from: 0, to: progress)
                .stroke(tint(metric), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        // No rotation. A capsule's path already begins at the top of its own straight
        // edge; turning it would turn the shape, not the starting point.
        .animation(.smooth(duration: 0.9), value: metric.value)
    }
}
