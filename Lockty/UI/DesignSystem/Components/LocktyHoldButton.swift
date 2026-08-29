import SwiftUI

/// The button for anything that commits: creating a routine, ending one.
///
/// Held rather than tapped, and the holding is the whole design. An aura swells inside
/// the glass as the press goes on and the fill closes behind it, so the button shows how
/// far in you are instead of asking you to trust a timer you cannot see. Letting go
/// before the end drains it back and nothing happens.
struct LocktyHoldButton: View {
    let title: String
    var systemImage: String?
    /// How long the press has to be held.
    var duration: Double = 1.1
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
            .background(alignment: .leading) { aura }
            .background(alignment: .leading) { fill }
            .clipShape(Capsule(style: .continuous))
            .safeGlass(radius: 999, interactive: true)
            .clipShape(Capsule(style: .continuous))
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
            .accessibilityHint("Mantén pulsado")
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

    /// The glow that swells from where the press lands. Blurred well past its own edge so
    /// it reads as light inside the glass rather than a shape sliding across it.
    private var aura: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [tint.opacity(0.85), tint.opacity(0.15), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: 90
                )
            )
            .frame(width: 120, height: 120)
            .scaleEffect(0.35 + progress * 2.4)
            .opacity(progress == 0 ? 0 : 0.9)
            .blur(radius: 26)
            .offset(x: -20)
            .allowsHitTesting(false)
    }

    /// Closes in behind the aura, so the button is visibly full at the moment it fires.
    private var fill: some View {
        GeometryReader { proxy in
            Capsule(style: .continuous)
                .fill(tint.opacity(0.22))
                .frame(width: proxy.size.width * progress)
        }
        .allowsHitTesting(false)
    }

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
