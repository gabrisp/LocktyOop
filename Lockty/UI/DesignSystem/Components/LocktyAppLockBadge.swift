import FamilyControls
import ManagedSettings
import SwiftUI

/// An app's icon with its lock state drawn around it.
///
/// One component for every place an app is shown as blocked or released -- the unlock
/// request, the active mode card, the mode sheet -- so they can't drift apart.
///
/// While an allowance is running the border doubles as its timer: it is a full ring at
/// the moment of unlocking and unwinds to nothing as the time runs out, at which point
/// the lock and the whole border come back.
struct LocktyAppLockBadge: View {
    let token: ApplicationToken?
    /// Scales the finished badge. It no longer sets the icon's size -- nothing can --
    /// so it is a multiplier on the whole thing, ring included.
    var scale: CGFloat = 1.7
    /// When the running allowance began and ends. Nil means the app is simply locked.
    var unlockedFrom: Date?
    var unlockedUntil: Date?
    var showsBorder = true
    /// What sits under the badge. `.none` when the badge is the whole story.
    var caption: Caption = .none

    enum Caption: Equatable {
        case none
        /// A call to action, e.g. "Desbloquear ahora".
        case action(String)
        /// The time left on the running allowance, counted down live.
        case remainingTime
    }

    private var borderWidth: CGFloat { 2 }
    /// The transparent gap between the icon and its ring.
    private var inset: CGFloat { 2 }

    /// The icon's own drawn size, measured rather than imposed.
    ///
    /// Forcing a width and a height on Label(token) was the whole problem: FamilyControls
    /// draws it at its own size inside whatever frame it is handed, so a bigger frame
    /// only ever bought more empty space around a same-sized icon. The badge is now the
    /// icon plus two points, and the ring is drawn around that.
    @State private var iconSize: CGFloat = 0

    private var borderRadius: CGFloat {
        iconSize * 0.23 + inset
    }

    private var isUnlocked: Bool {
        guard let unlockedUntil else { return false }
        return unlockedUntil > Date()
    }

    var body: some View {
        // TimelineView only while an allowance is running: a locked badge has nothing to
        // animate and shouldn't be redrawing every frame.
        Group {
            if unlockedUntil != nil {
                TimelineView(.animation) { context in
                    badge(at: context.date)
                }
            } else {
                badge(at: Date())
            }
        }
    }

    @ViewBuilder
    private func captionLabel(at date: Date) -> some View {
        switch caption {
        case .none:
            EmptyView()

        case .action(let title):
            Text(title)
                .font(.system(.caption, design: .default, weight: .medium))
                .foregroundStyle(LocktyColors.productive)
                .lineLimit(1)

        case .remainingTime:
            Text(remainingTimeText(at: date))
                .font(.system(.caption, design: .default, weight: .medium))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .animation(.snappy(duration: 0.25), value: remainingTimeText(at: date))
                .foregroundStyle(LocktyColors.primaryText)
                .lineLimit(1)
        }
    }

    /// mm:ss while an allowance is running, and nothing once it has expired.
    private func remainingTimeText(at date: Date) -> String {
        guard let unlockedUntil else { return "" }
        let remaining = max(0, Int(unlockedUntil.timeIntervalSince(date).rounded(.up)))
        return String(format: "%d:%02d", remaining / 60, remaining % 60)
    }

    private func badge(at date: Date) -> some View {
        let progress = remainingProgress(at: date)
        let locked = progress <= 0

        return icon
            // Measured, never framed: the badge takes the icon's size, not the other way
            // round. No clip either -- Apple draws Label(token) with its own bleed.
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { newValue in
                iconSize = newValue
            }
            .overlay {
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: max(iconSize * 0.34, 14), weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 5)
                }
            }
            .padding(inset)
            .overlay {
                if showsBorder {
                    RoundedRectangle(cornerRadius: borderRadius, style: .continuous)
                        // Locked draws the whole ring; unlocked unwinds it as the
                        // allowance is spent, so what is left of the border is what is
                        // left of the time.
                        .trim(from: 0, to: locked ? 1 : progress)
                        .stroke(
                            LocktyColors.productive.opacity(locked ? 0.7 : 0.95),
                            style: StrokeStyle(lineWidth: borderWidth, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }
            }
            // Scaled as one piece -- icon, gap and ring together -- so the proportions
            // set above survive whatever size a caller wants the badge at.
            .scaleEffect(scale)
            // scaleEffect draws bigger without laying out bigger, so the row would still
            // reserve the unscaled size and the badges would overlap. This claims the
            // space the scaled badge actually occupies.
            .frame(width: scaledWidth, height: scaledSide)
            .overlay(alignment: .bottom) {
                captionLabel(at: date)
                    .fixedSize()
                    .offset(y: 18)
            }
            .padding(.bottom, caption == .none ? 0 : 20)
    }

    /// The finished badge's side: the measured icon, its gap, and the scale applied.
    private var scaledSide: CGFloat? {
        guard iconSize > 0 else { return nil }
        return (iconSize + inset * 2) * scale
    }

    /// A little wider than it is tall. The caption underneath is laid out at its natural
    /// width and would otherwise run into the badge either side of it.
    private var scaledWidth: CGFloat? {
        scaledSide.map { $0 + 10 }
    }

    /// FamilyControls draws `Label(token)` at its own size and ignores the frame it is
    /// given, so the icon sat small in the middle of the badge no matter how large the
    /// badge was. Scaling it is the only thing that actually grows it; the font is set
    /// too, for the versions that do honour it.
    @ViewBuilder
    private var icon: some View {
        if let token {
            Label(token)
                .labelStyle(.iconOnly)
                .id(token)
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LocktyColors.elevatedBackground)
                .frame(width: 52, height: 52)
        }
    }

    /// How much of the allowance is left, 1 at the moment of unlocking and 0 once it has
    /// run out.
    private func remainingProgress(at date: Date) -> CGFloat {
        guard let unlockedUntil, let unlockedFrom else { return 0 }
        let total = unlockedUntil.timeIntervalSince(unlockedFrom)
        guard total > 0 else { return 0 }
        let remaining = unlockedUntil.timeIntervalSince(date)
        return CGFloat(min(max(remaining / total, 0), 1))
    }
}
