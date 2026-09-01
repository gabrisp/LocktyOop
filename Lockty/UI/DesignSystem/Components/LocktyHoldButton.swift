import SwiftUI

/// The button for anything that commits: creating a routine, ending one.
///
/// Held rather than tapped, and the holding is the whole design. An aura swells inside
/// the glass as the press goes on until it has washed over the whole button, so it shows
/// how far in you are instead of asking you to trust a timer you cannot see. Letting go
/// before the end drains it back and nothing happens.
struct LocktyHoldButton: View {
    let title: String
    var systemImage: String?
    /// How long the press has to be held.
    ///
    /// Long enough to be a decision rather than a tap that took a moment. It is also the
    /// window the light has to fill in: at a second the scattered points barely got going
    /// before the action fired, so most of what the button does was never seen.
    var duration: Double = 1.7
    var tint: Color = LocktyColors.productive
    let action: () -> Void

    @State private var progress: CGFloat = 0
    @State private var isHolding = false
    @State private var isCompleted = false
    @State private var holdTask: Task<Void, Never>?

    /// Steps the haptic ticks, so they come as a quickening pulse rather than one per
    /// frame. The intensity rides the progress, so the button is felt closing.
    private var hapticStep: Int {
        Int(progress * 8)
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background { aura }
            .clipShape(Capsule(style: .continuous))
            .safeGlass(radius: 999, interactive: true)
            .clipShape(Capsule(style: .continuous))
            // A rim in a lighter cast of the tint, there before anything is pressed.
            // Glass on a dark screen has almost no edge of its own, so the button had no
            // shape until you touched it -- this is what says where it is.
            .overlay {
                Capsule(style: .continuous)
                    .stroke(tint.opacity(0.30), lineWidth: 1)
            }
            // Running only while the button is being held: the light going round the rim
            // is the button saying it is working on it, which is only true then.
            .locktyBorderBeam(
                beam: [tint, .white, tint.opacity(0.6)],
                beamBlur: 12,
                cornerRadius: 30,
                isEnabled: isHolding && !isCompleted
            )
            .scaleEffect(isHolding ? 0.98 : 1)
            .animation(.snappy(duration: 0.2), value: isHolding)
            .contentShape(Capsule(style: .continuous))
            .onLongPressGesture(minimumDuration: duration) {
                complete()
            } onPressingChanged: { isPressing in
                if isPressing {
                    beginHold()
                } else {
                    cancelHold()
                }
            }
            .sensoryFeedback(trigger: hapticStep) { _, _ in
                guard isHolding, progress > 0, progress < 1 else { return nil }
                return .impact(weight: .light, intensity: 0.25 + 0.75 * Double(progress))
            }
            .sensoryFeedback(.success, trigger: isCompleted) { _, new in new }
            .accessibilityLabel(title)
            .accessibilityHint("Press and hold")
    }

    private var content: some View {
        HStack(spacing: LocktySpacing.sm) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .regular))
            }

            Text(title)
                .font(.system(.headline, design: .default, weight: .semibold))
        }
        .foregroundStyle(LocktyColors.primaryText)
    }

    /// The fill: a scattering of lights that come up one after another and add together.
    ///
    /// It used to be a single circle growing from the left edge, which is a progress bar
    /// wearing a blur -- you could read exactly how far along you were from where its
    /// edge had got to, and it always filled in the same direction at the same rate.
    /// This lights seeded points across the button in a scattered order instead. Each one
    /// swells from nothing, they overlap, and because they are added rather than drawn
    /// over each other the overlaps burn brighter, so the button reads as filling with
    /// light rather than as a bar being drawn.
    private var aura: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(Self.seeds) { seed in
                    let local = seedProgress(seed)

                    Circle()
                        .fill(tint)
                        .frame(
                            width: seedDiameter(seed, in: proxy.size, local: local),
                            height: seedDiameter(seed, in: proxy.size, local: local)
                        )
                        .blur(radius: 18)
                        // A floor under the press, not a change to it: at rest every
                        // light sits at the same faint value, which is the imperfect
                        // scatter that gives the button a shape before it is touched.
                        // The moment a hold starts, `local` takes over from zero and the
                        // press behaves exactly as it did.
                        .opacity(Self.restingOpacity + 0.42 * local)
                        .position(
                            x: proxy.size.width * seed.x,
                            y: proxy.size.height * seed.y
                        )
                }
            }
            // Added, not stacked: where two lights overlap the result is brighter than
            // either, which is what makes a crowd of them read as one filling glow.
            .blendMode(.plusLighter)
            .compositingGroup()
        }
        .allowsHitTesting(false)
    }

    /// How lit one seed is, 0 until the hold passes its threshold and 1 by the end.
    private func seedProgress(_ seed: AuraSeed) -> CGFloat {
        guard progress > seed.threshold else { return 0 }
        let span = max(1 - seed.threshold, 0.001)
        return min((progress - seed.threshold) / span, 1)
    }

    private func seedDiameter(_ seed: AuraSeed, in size: CGSize, local: CGFloat) -> CGFloat {
        let full = size.height * seed.scale
        return full * (0.35 + 0.65 * local)
    }

    /// How lit the scatter is with nothing pressed. Faint enough to be a texture rather
    /// than a fill -- the button was invisible on a dark screen until it was touched.
    private static let restingOpacity: Double = 0.07

    /// Where the lights are and the order they come up in.
    ///
    /// Fixed rather than generated per press. Truly random points would jump on every
    /// frame of the hold, and re-seeding on each press would make the button behave
    /// differently every time it is used -- the scatter should look arbitrary, not be
    /// unpredictable. The thresholds are deliberately out of order so they light across
    /// the button rather than sweeping along it.
    private struct AuraSeed: Identifiable {
        let id: Int
        let x: CGFloat
        let y: CGFloat
        let scale: CGFloat
        let threshold: CGFloat
    }

    private static let seeds: [AuraSeed] = {
        let points: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (0.14, 0.55, 2.2, 0.00),
            (0.72, 0.40, 1.9, 0.08),
            (0.38, 0.62, 2.4, 0.14),
            (0.90, 0.60, 1.7, 0.22),
            (0.26, 0.36, 1.8, 0.30),
            (0.58, 0.70, 2.1, 0.38),
            (0.05, 0.42, 1.6, 0.46),
            (0.82, 0.30, 2.0, 0.54),
            (0.46, 0.30, 1.7, 0.62),
            (0.66, 0.62, 2.3, 0.70)
        ]
        return points.enumerated().map { index, point in
            AuraSeed(id: index, x: point.0, y: point.1, scale: point.2, threshold: point.3)
        }
    }()

    private func beginHold() {
        guard !isCompleted else { return }
        isHolding = true
        holdTask?.cancel()

        holdTask = Task { @MainActor in
            let started = Date()
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(started)
                let newValue = min(CGFloat(elapsed / duration), 1)
                progress = newValue
                if newValue >= 1 { return }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    private func cancelHold() {
        holdTask?.cancel()
        holdTask = nil
        isHolding = false
        guard !isCompleted else { return }
        // Drains rather than snapping to nothing: letting go should look like the button
        // emptying, not like it was never pressed.
        withAnimation(.smooth(duration: 0.25)) { progress = 0 }
    }

    private func complete() {
        holdTask?.cancel()
        holdTask = nil
        isHolding = false
        withAnimation(.smooth(duration: 0.18)) {
            progress = 1
            isCompleted = true
        }
        action()

        // Reset so the button can be held again if the screen it is on stays put.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            withAnimation(.smooth(duration: 0.3)) {
                progress = 0
                isCompleted = false
            }
        }
    }
}
