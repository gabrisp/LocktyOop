import SwiftUI

/// The productivity score, as a lit rock rather than a number in a box.
///
/// The whole thing arrives rather than appearing: the aura starts at nothing and the
/// glow behind the number starts at nothing with it. As the number climbs, the light
/// comes up with it, so the colour reads as the verdict on the number rather than as
/// decoration that was there all along.
///
/// Depth comes from three separate shadows, not from one:
/// - outside, a wide bloom of the score's colour;
/// - inside, darkness pressing in from the rim in the app's own background, which is
///   what makes it read as a solid body rather than a flat disc;
/// - and from the middle, a very faint wash of the colour lifting the centre.
///
/// Drawn inside a `compositingGroup` so all of it composites as one object. Without it
/// each layer blends against the screen separately and the edge shows through its halo.
struct ProductivityAuraView: View {
    /// 0 to 100. Nil while the day's score is still unknown.
    let score: Int?
    /// 0 at rest, 1 once the screen has been scrolled past the collapse distance.
    /// Everything shrinks by it; only the word above the number goes away.
    var collapseProgress: CGFloat = 0

    /// Climbs to `score` once the view is on screen. Separate from the score itself so
    /// re-rendering for any other reason does not restart the arrival.
    @State private var displayedScore = 0

    private let side: CGFloat = 240

    /// Small enough to sit on the toolbar's line, large enough that the number is still
    /// the thing you read. The rock keeps its shape and its light all the way down:
    /// collapsing is the same object seen from further away, not a second badge.
    private var scale: CGFloat {
        MetricsHeaderGeometry.lerp(1, 0.3, progress: collapseProgress)
    }

    /// Green at the top, yellow in the middle, red at the bottom -- green being the end
    /// worth reaching.
    ///
    /// The thresholds are `DailyScoreTone`'s, not this view's. They are the same bands
    /// every other score in the app is judged by, and a second set here would have the
    /// rock disagreeing with the cards under it about the same number.
    private var accent: Color {
        guard let score else { return LocktyColors.secondaryText }
        switch DailyScoreTone.tone(for: Double(score)) {
        case .weak:
            return LocktyColors.unproductive
        case .balanced:
            return LocktyColors.warning
        case .strong:
            return LocktyColors.productive
        }
    }

    /// How far the count has travelled. The light is tied to this rather than to a timer
    /// of its own, so it comes up with the digits instead of after them.
    private var arrival: Double {
        guard let score, score > 0 else { return score == nil ? 0 : 1 }
        return min(Double(displayedScore) / Double(score), 1)
    }

    var body: some View {
        ZStack {
            outerBloom
            body(of: RockShape())
            label
        }
        // Laid out at the height it actually fills, not at the square its layers are
        // measured against. The rock is drawn at 76% of `side` and the bloom at 90%, so a
        // full square claimed a band of empty space above and below it -- which is what
        // made the badge sit too low, and what dragging it back up with negative padding
        // was papering over.
        .frame(width: side, height: side * 0.82)
        .compositingGroup()
        .scaleEffect(scale)
        // Claims the space it draws at rather than the space it was laid out at, so the
        // content below rides up as it shrinks instead of leaving a hole behind.
        .frame(width: side * scale, height: side * 0.82 * scale)
        .task(id: score) {
            await arrive()
        }
    }

    // MARK: - Layers

    /// The bloom the rock sits in. A blurred copy of the same silhouette, so the light
    /// follows the shape instead of being a circle behind an irregular thing.
    private var outerBloom: some View {
        RockShape()
            .fill(accent)
            .frame(width: side * 0.9, height: side * 0.9)
            .blur(radius: 46)
            .opacity(0.8 * arrival)
            .animation(.smooth(duration: 0.9), value: arrival)
            .animation(.smooth(duration: 0.6), value: accent)
    }

    private func body(of shape: RockShape) -> some View {
        shape
            // Nearly black, with just enough of the colour in it to belong to the bloom
            // around it rather than being a hole cut in it.
            .fill(accent.opacity(0.16))
            .background {
                shape.fill(LocktyColors.background)
            }
            // From the middle: a very faint lift, so the body is not evenly dark and the
            // speckles have something to sit in.
            .overlay {
                RadialGradient(
                    colors: [accent.opacity(0.22), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: side * 0.36
                )
                .blendMode(.plusLighter)
                .mask { shape }
                .opacity(arrival)
            }
            .overlay {
                SpeckleField()
                    .opacity(0.9 * arrival)
                    .mask { shape }
            }
            // From the rim inward, in the app's own background. A wide stroke blurred and
            // clipped to the inside of the shape: the edges go darker than the middle,
            // which is what turns a flat silhouette into something with a body.
            .overlay {
                shape
                    .stroke(LocktyColors.background, lineWidth: 26)
                    .blur(radius: 16)
                    .mask { shape }
            }
            .frame(width: side * 0.76, height: side * 0.76)
            .animation(.smooth(duration: 0.6), value: accent)
    }

    /// White type, with the colour behind it rather than in it.
    ///
    /// The number used to turn the accent colour on arrival, which fought the rock it
    /// sits on. An added glow reads as the number being lit by what is under it, and
    /// keeps the digits legible at any score.
    private var label: some View {
        labelContent
            .foregroundStyle(.white)
            .background {
                labelContent
                    .foregroundStyle(accent)
                    .blur(radius: 14)
                    .blendMode(.plusLighter)
                    .opacity(0.95 * arrival)
            }
    }

    private var labelContent: some View {
        VStack(spacing: -4) {
            Text("Productivity")
                .font(.system(.subheadline, design: .default, weight: .semibold))
                // The only thing that leaves. At a third the size it would be unreadable
                // anyway, and the number alone is still the whole point.
                .opacity(1 - Double(MetricsHeaderGeometry.rangedProgress(collapseProgress, from: 0, to: 0.5)))

            Text("\(displayedScore)")
                .font(.system(size: 76, weight: .heavy, design: .default))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.smooth(duration: 1.1), value: displayedScore)
        }
    }

    // MARK: - Arrival

    @MainActor
    private func arrive() async {
        guard let score else {
            displayedScore = 0
            return
        }

        displayedScore = 0

        // One turn, so the zero is on screen before the climb starts. Setting both in the
        // same pass gives SwiftUI nothing to animate between and the number simply
        // appears at its final value.
        try? await Task.sleep(for: .milliseconds(120))
        guard !Task.isCancelled else { return }

        withAnimation(.smooth(duration: 1.1)) {
            displayedScore = score
        }
    }
}

/// A closed shape that is nowhere a circle.
///
/// Twelve points at uneven radii, joined by quadratic curves through their midpoints --
/// each point becomes a control rather than a corner, so the outline stays smooth while
/// never settling into an arc. Four segments were not enough: at that count the eye still
/// reads a circle that has been nudged.
///
/// The radii are fixed, not random. This view redraws on every tick of the count, and a
/// shape that reshuffled each frame would boil rather than sit there.
private struct RockShape: Shape {
    private static let radii: [CGFloat] = [
        1.00, 0.92, 0.99, 0.87, 0.97, 0.90,
        1.02, 0.93, 0.98, 0.88, 1.00, 0.94
    ]

    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let count = Self.radii.count

        func point(at index: Int) -> CGPoint {
            let wrapped = ((index % count) + count) % count
            let angle = (CGFloat(wrapped) / CGFloat(count)) * 2 * .pi - .pi / 2
            let distance = radius * Self.radii[wrapped]
            return CGPoint(
                x: centre.x + cos(angle) * distance,
                y: centre.y + sin(angle) * distance
            )
        }

        func midpoint(_ first: CGPoint, _ second: CGPoint) -> CGPoint {
            CGPoint(x: (first.x + second.x) / 2, y: (first.y + second.y) / 2)
        }

        var path = Path()
        path.move(to: midpoint(point(at: count - 1), point(at: 0)))

        for index in 0..<count {
            path.addQuadCurve(
                to: midpoint(point(at: index), point(at: index + 1)),
                control: point(at: index)
            )
        }

        path.closeSubpath()
        return path
    }
}

/// The dust inside the rock. Positions are fixed for the same reason the shape is: this
/// view redraws on every tick of the count, and specks that jumped each frame would look
/// like noise rather than depth.
private struct SpeckleField: View {
    private static let specks: [(x: CGFloat, y: CGFloat, size: CGFloat, opacity: Double)] = {
        let seeds: [(CGFloat, CGFloat)] = [
            (0.18, 0.30), (0.32, 0.16), (0.47, 0.34), (0.61, 0.21), (0.74, 0.38),
            (0.24, 0.52), (0.40, 0.62), (0.55, 0.49), (0.69, 0.60), (0.82, 0.47),
            (0.29, 0.74), (0.44, 0.83), (0.58, 0.72), (0.71, 0.81), (0.36, 0.44),
            (0.63, 0.30), (0.50, 0.90), (0.22, 0.63), (0.78, 0.68), (0.52, 0.24),
            (0.66, 0.44), (0.34, 0.68), (0.48, 0.58), (0.60, 0.86), (0.26, 0.42)
        ]
        return seeds.enumerated().map { index, seed in
            let size = 1.3 + CGFloat((index * 7) % 5) * 0.7
            let opacity = 0.22 + Double((index * 3) % 6) * 0.12
            return (seed.0, seed.1, size, opacity)
        }
    }()

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(Array(Self.specks.enumerated()), id: \.offset) { _, speck in
                    Circle()
                        .fill(Color.white)
                        .frame(width: speck.size, height: speck.size)
                        .opacity(speck.opacity)
                        .blur(radius: 0.4)
                        .position(
                            x: proxy.size.width * speck.x,
                            y: proxy.size.height * speck.y
                        )
                }
            }
        }
    }
}
