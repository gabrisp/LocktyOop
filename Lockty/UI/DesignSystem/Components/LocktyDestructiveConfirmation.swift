import SwiftUI

/// The screen that asks before something is deleted.
///
/// One of these, used by everything that deletes: a rule, a routine, a pause, a group. An
/// alert would do the job, but an alert is the same two lines of grey text whatever it is
/// asking about, and deleting a rule you built is not the same weight of decision as
/// dismissing a message. This says what is going, in the shape the rest of the app uses
/// to say anything else -- a glyph lit by its own colour, a sentence, and a button held
/// rather than tapped.
///
/// The hold is the point. Everything that commits in Lockty is held, and deleting is the
/// one action with nothing behind it to undo it.
struct LocktyDestructiveConfirmation: View {
    /// What is going. "Delete this rule?" -- the question, not a heading.
    let title: String
    /// What deleting it actually costs, in a sentence.
    let message: String
    var confirmTitle = "Hold to delete"
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: LocktySpacing.xl) {
            badge

            VStack(spacing: LocktySpacing.sm) {
                Text(title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(LocktyColors.primaryText)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.system(.subheadline, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: LocktySpacing.md) {
                LocktyHoldButton(
                    title: confirmTitle,
                    systemImage: "trash",
                    tint: LocktyColors.error,
                    action: onConfirm
                )

                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(.headline, design: .default, weight: .semibold))
                        .foregroundStyle(LocktyColors.secondaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.locktyInteractive(shape: Capsule(style: .continuous)))
                .tappable()
            }
        }
        .padding(.horizontal, LocktySpacing.screenInset)
        .padding(.top, LocktySpacing.xxl)
        .padding(.bottom, LocktySpacing.sheetBottom(forTop: LocktySpacing.md))
        .frame(maxWidth: .infinity)
    }

    /// The trash, standing in its own red light.
    ///
    /// The same construction the score pills use: a blurred copy of the shape behind the
    /// shape, so the colour comes off the thing rather than sitting behind it as a
    /// square. Added on a dark ground and drawn plainly on a pale one -- there is no
    /// light to add to white.
    @Environment(\.colorScheme) private var colorScheme

    private var badge: some View {
        let side: CGFloat = 88
        let isDark = colorScheme == .dark

        return ZStack {
            Circle()
                .fill(LocktyColors.error)
                .frame(width: side, height: side)
                .blur(radius: 26)
                .opacity(isDark ? 0.55 : 0.28)
                .blendMode(isDark ? .plusLighter : .normal)

            Circle()
                .fill(LocktyColors.error.opacity(isDark ? 0.16 : 0.12))
                .frame(width: side, height: side)
                .overlay {
                    Circle()
                        .stroke(LocktyColors.error.opacity(0.35), lineWidth: 1)
                }

            Image(systemName: "trash")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(LocktyColors.error)
        }
        .frame(width: side, height: side)
    }
}
