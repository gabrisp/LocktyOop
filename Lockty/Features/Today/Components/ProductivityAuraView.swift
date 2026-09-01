import SwiftUI

/// The productivity score, as a lit rock rather than a number in a box.
///
/// The whole thing arrives rather than appearing: the aura starts at nothing and the
/// number starts white and at zero. As the number climbs, the glow comes up with it, and
/// only when it lands does the colour arrive -- so the colour reads as the verdict on the
/// number, not as decoration that was there all along.
///
/// Drawn inside a `compositingGroup` so the blur, the glow and the speckles composite as
/// one object. Without it each layer blends against the screen separately and the edge
/// of the shape shows through its own halo.
struct ProductivityAuraView: View {
    /// 0 to 100. Nil while the day's score is still unknown.
    let score: Int?

    /// Climbs to `score` once the view is on screen. Separate from the score itself so
    /// re-rendering for any other reason does not restart the arrival.
    @State private var displayedScore = 0
    @State private var hasArrived = false

    private let side: CGFloat = 240

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

    /// White until the number has landed, then the colour it earned.
    private var numberColor: Color {
        hasArrived ? accent : LocktyColors.primaryText
    }

    /// Nothing at first, full once the number is home. Driven by how far the count has
    /// travelled so the light comes up with the digits rather than after them.
    private var arrivalProgress: Double {
        guard let score, score > 0 else { return hasArrived ? 1 : 0 }
        return min(Double(displayedScore) / Double(score), 1)
    }

    var body: some View {
        ZStack {
            aura
            rock
            label
        }
        .frame(width: side, height: side)
        .compositingGroup()
        .task(id: score) {
            await arrive()
        }
    }

    // MARK: - Layers

    /// The glow the rock sits in. A blurred copy of the same shape, so the light follows
    /// the silhouette instead of being a circle behind an irregular thing.
    private var aura: some View {
        RockShape()
            .fill(accent)
            .frame(width: side * 0.92, height: side * 0.92)
            .blur(radius: 42)
            .opacity(0.75 * arrivalProgress)
            .animation(.smooth(duration: 0.9), value: arrivalProgress)
            .animation(.smooth(duration: 0.6), value: accent)
    }

    private var rock: some View {
        RockShape()
            .fill(
                // Dark in the middle and lifting towards the rim, which is what stops it
                // reading as a flat blob cut out of the glow behind it.
                RadialGradient(
                    colors: [
                        accent.opacity(0.10),
                        accent.opacity(0.34)
                    ],
                    center: .center,
                    startRadius: 4,
                    endRadius: side * 0.55
                )
            )
            .frame(width: side * 0.78, height: side * 0.78)
            .overlay {
                SpeckleField()
                    .frame(width: side * 0.78, height: side * 0.78)
                    .opacity(0.9 * arrivalProgress)
                    .mask { RockShape() }
            }
            .animation(.smooth(duration: 0.6), value: accent)
    }

    private var label: some View {
        VStack(spacing: -2) {
            Text("Productivity")
                .font(.system(.subheadline, design: .default, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.86))

            Text("\(displayedScore)")
                .font(.system(size: 74, weight: .heavy, design: .default))
                .foregroundStyle(numberColor)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.smooth(duration: 1.1), value: displayedScore)
                .animation(.smooth(duration: 0.5), value: numberColor)
        }
        .shadow(color: .black.opacity(0.35), radius: 12, y: 2)
    }

    // MARK: - Arrival

    @MainActor
    private func arrive() async {
        guard let score else {
            displayedScore = 0
            hasArrived = false
            return
        }

        displayedScore = 0
        hasArrived = false

        // One turn, so the zero is on screen before the climb starts. Setting both in the
        // same pass gives SwiftUI nothing to animate between and the number simply
        // appears at its final value.
        try? await Task.sleep(for: .milliseconds(120))
        guard !Task.isCancelled else { return }

        withAnimation(.smooth(duration: 1.1)) {
            displayedScore = score
        }

        // The colour lands when the number does, not while it is still moving.
        try? await Task.sleep(for: .milliseconds(1_050))
        guard !Task.isCancelled else { return }
        withAnimation(.smooth(duration: 0.5)) {
            hasArrived = true
        }
    }
}

/// A circle that isn't one.
///
/// Built from four cubic segments whose radii differ, so each quadrant bulges by a
/// different amount. A real circle reads as a progress ring or a badge; the point here is
/// something with weight to it.
private struct RockShape: Shape {
    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2

        // Fixed, not random: the shape has to be the same on every redraw, and this view
        // redraws on every tick of the count.
        let radii: [CGFloat] = [1.0, 0.94, 1.02, 0.96]
        let control: CGFloat = 0.5523

        func point(_ index: Int) -> CGPoint {
            let angle = CGFloat(index) * .pi / 2 - .pi / 2
            let r = radius * radii[index % radii.count]
            return CGPoint(x: centre.x + cos(angle) * r, y: centre.y + sin(angle) * r)
        }

        var path = Path()
        path.move(to: point(0))

        for index in 0..<4 {
            let from = point(index)
            let to = point(index + 1)
            let handle = radius * control * radii[index % radii.count]

            let fromAngle = CGFloat(index) * .pi / 2 - .pi / 2
            let toAngle = CGFloat(index + 1) * .pi / 2 - .pi / 2

            let control1 = CGPoint(
                x: from.x + cos(fromAngle + .pi / 2) * handle,
                y: from.y + sin(fromAngle + .pi / 2) * handle
            )
            let control2 = CGPoint(
                x: to.x + cos(toAngle - .pi / 2) * handle,
                y: to.y + sin(toAngle - .pi / 2) * handle
            )

            path.addCurve(to: to, control1: control1, control2: control2)
        }

        path.closeSubpath()
        return path
    }
}

/// The dust inside the rock. Positions are fixed rather than random for the same reason
/// the shape is: this view redraws on every tick of the count, and specks that jump on
/// each frame would look like noise rather than depth.
private struct SpeckleField: View {
    private static let specks: [(x: CGFloat, y: CGFloat, size: CGFloat, opacity: Double)] = {
        var generator = SystemRandomNumberGenerator()
        _ = generator
        // Laid out by hand from a fixed seed pattern so the field is stable across builds.
        let seeds: [(CGFloat, CGFloat)] = [
            (0.18, 0.30), (0.32, 0.16), (0.47, 0.34), (0.61, 0.21), (0.74, 0.38),
            (0.24, 0.52), (0.40, 0.62), (0.55, 0.49), (0.69, 0.60), (0.82, 0.47),
            (0.29, 0.74), (0.44, 0.83), (0.58, 0.72), (0.71, 0.81), (0.36, 0.44),
            (0.63, 0.30), (0.50, 0.90), (0.22, 0.63), (0.78, 0.68), (0.52, 0.24)
        ]
        return seeds.enumerated().map { index, seed in
            let size = 1.4 + CGFloat((index * 7) % 5) * 0.7
            let opacity = 0.25 + Double((index * 3) % 6) * 0.11
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
