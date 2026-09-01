import FamilyControls
import ManagedSettings
import SwiftUI

/// The frame every full-screen flow step is drawn inside.
///
/// The chrome belongs to the parent and never moves: the close button, the title, the
/// two buttons at the bottom. Only the middle is swapped, and it crossfades through a
/// blur so a step change reads as the same screen thinking rather than a new one
/// arriving. The step chooses the primary button's label -- the button itself is the
/// parent's, so it stays put across the swap.
struct LocktyFlowScreen<Content: View>: View {
    let title: String
    /// Changing this is what animates the middle. It is the step's identity, not its
    /// content, so a step can update itself without triggering the transition.
    let stepID: AnyHashable
    let primaryTitle: String
    var secondaryTitle: String?
    var isPrimaryEnabled = true
    /// Seconds the primary button is held shut for when this step appears. The rest is
    /// the whole point of the flow: it is what makes opening the app a decision rather
    /// than a reflex, so it runs on every step that has one, every time.
    var restSeconds: Int = 0
    /// The chip in the top right. Tapping it takes the flow back to that choice.
    var accessoryToken: ApplicationToken?
    var onAccessory: (() -> Void)?
    let onClose: () -> Void
    let onPrimary: () -> Void
    var onSecondary: (() -> Void)?
    @ViewBuilder var content: Content

    /// Counts down from restSeconds. Restarted whenever the step changes, so each step
    /// gets its own wait rather than inheriting whatever was left of the last one.
    @State private var remainingRest = 0

    private var isResting: Bool { remainingRest > 0 }

    private var canPressPrimary: Bool { isPrimaryEnabled && !isResting }

    var body: some View {
        ZStack {
            LocktyScreenBackground()
                .ignoresSafeArea()

            // The content owns the whole screen and the chrome is laid over it, rather
            // than the three of them sharing a stack. Sharing one meant the content was
            // centred on whatever was left between two bars and the wheel was cut short
            // by them; overlaid, it runs the full height and the chrome floats on top.
            VStack(spacing: LocktySpacing.xl) {
                Text(title)
                    .font(.system(.title2, design: .default, weight: .bold))
                    .foregroundStyle(LocktyColors.primaryText)
                    // Same transition as the content, keyed on the title itself: the
                    // whole step should change together rather than the copy snapping
                    // while the thing it describes fades.
                    .transition(.blurReplace.combined(with: .opacity))
                    .id(title)

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.blurReplace.combined(with: .opacity))
                    .id(stepID)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Clear of the chrome laid over it, so the wheel can run as tall as it likes
            // without its ends sitting under the buttons.
            .padding(.top, 60)
            .padding(.bottom, 110)
            .overlay(alignment: .top) { header }
            .overlay(alignment: .bottom) { footer }
            .padding(.horizontal, LocktySpacing.lg)
        }
        .animation(.smooth(duration: 0.34), value: stepID)
        .task(id: stepID) {
            remainingRest = restSeconds
            while remainingRest > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                remainingRest -= 1
            }
        }
    }

    private var header: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(LocktyColors.primaryText)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(LocktyColors.elevatedBackground))
            }
            .buttonStyle(.locktyInteractive(shape: Circle()))
            .tappable()

            Spacer(minLength: 0)

            if let accessoryToken, let onAccessory {
                Button(action: onAccessory) {
                    HStack(spacing: LocktySpacing.sm) {
                        Label(accessoryToken)
                            .labelStyle(.iconOnly)
                            .id(accessoryToken)
                            .frame(width: 30, height: 30)

                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(LocktyColors.secondaryText)
                    }
                    .padding(.horizontal, LocktySpacing.md)
                    .padding(.vertical, 7)
                    .background(Capsule(style: .continuous).fill(LocktyColors.elevatedBackground))
                }
                .buttonStyle(.locktyInteractive(shape: Capsule(style: .continuous)))
                .tappable()
                .transition(.blurReplace.combined(with: .opacity))
            }
        }
    }

    private var footer: some View {
        VStack(spacing: LocktySpacing.md) {
            Button(action: onPrimary) {
                Text(isResting ? "\(remainingRest)" : primaryTitle)
                    .font(.system(.headline, design: .default, weight: .semibold))
                    .monospacedDigit()
                    // Counting stays a numeric transition; changing what the button is
                    // for is a blur replace, like everything else in the step.
                    .contentTransition(isResting ? .numericText(countsDown: true) : .identity)
                    .transition(.blurReplace.combined(with: .opacity))
                    .id(isResting ? "rest" : primaryTitle)
                    .animation(.snappy(duration: 0.25), value: remainingRest)
                    .foregroundStyle(LocktyColors.onPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background(Capsule(style: .continuous).fill(isResting ? LocktyColors.ink(0.55) : .white))
                    .clipShape(Capsule(style: .continuous))
            }
            .buttonStyle(.locktyInteractive(shape: Capsule(style: .continuous)))
            .tappable()
            .disabled(!canPressPrimary)
            .opacity(isPrimaryEnabled ? 1 : 0.4)
            .animation(.smooth(duration: 0.3), value: isResting)
            // Ticks that firm up as the wait runs out, and a solid one when it opens.
            .sensoryFeedback(trigger: remainingRest) { _, new in
                guard new > 0, restSeconds > 0 else { return nil }
                let elapsed = 1 - Double(new) / Double(restSeconds)
                return .impact(weight: .light, intensity: 0.25 + 0.75 * elapsed)
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: isResting) { _, new in !new }

            if let secondaryTitle, let onSecondary {
                Button(action: onSecondary) {
                    Text(secondaryTitle)
                        .font(.system(.headline, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.secondaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .contentShape(Capsule(style: .continuous))
                }
                // No background of its own: the capsule only shows up as the press
                // highlight, so the button is invisible until it is touched.
                .buttonStyle(.locktyInteractive(shape: Capsule(style: .continuous)))
                .tappable()
            }
        }
        .animation(.smooth(duration: 0.24), value: primaryTitle)
    }
}
