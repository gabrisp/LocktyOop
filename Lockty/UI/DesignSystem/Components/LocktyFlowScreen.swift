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
    /// The chip in the top right. Tapping it takes the flow back to that choice.
    var accessoryToken: ApplicationToken?
    var onAccessory: (() -> Void)?
    let onClose: () -> Void
    let onPrimary: () -> Void
    var onSecondary: (() -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            LocktyScreenBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                Text(title)
                    .font(.system(.title2, design: .default, weight: .bold))
                    .foregroundStyle(LocktyColors.primaryText)
                    .padding(.top, LocktySpacing.lg)

                Spacer(minLength: 0)

                content
                    .transition(.blurReplace.combined(with: .opacity))
                    .id(stepID)

                Spacer(minLength: 0)

                footer
            }
            .padding(.horizontal, LocktySpacing.lg)
            .padding(.bottom, LocktySpacing.lg)
        }
        .animation(.smooth(duration: 0.34), value: stepID)
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
            .buttonStyle(.plain)
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
                .buttonStyle(.plain)
                .tappable()
                .transition(.blurReplace.combined(with: .opacity))
            }
        }
    }

    private var footer: some View {
        VStack(spacing: LocktySpacing.md) {
            Button(action: onPrimary) {
                Text(primaryTitle)
                    .font(.system(.headline, design: .default, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .contentTransition(.opacity)
                    .background(Capsule(style: .continuous).fill(.white))
            }
            .buttonStyle(.locktyInteractive)
            .locktyInteractiveSurface(enabled: true, shape: Capsule(style: .continuous))
            .tappable()
            .disabled(!isPrimaryEnabled)
            .opacity(isPrimaryEnabled ? 1 : 0.4)

            if let secondaryTitle, let onSecondary {
                Button(action: onSecondary) {
                    Text(secondaryTitle)
                        .font(.system(.headline, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.secondaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                }
                .buttonStyle(.plain)
                .tappable()
            }
        }
        .animation(.smooth(duration: 0.24), value: primaryTitle)
    }
}
