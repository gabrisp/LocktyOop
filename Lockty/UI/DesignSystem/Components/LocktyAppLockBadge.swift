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
    var size: CGFloat = 72
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

    private var borderWidth: CGFloat { 2.5 }
    private var iconRadius: CGFloat { size * 0.24 }
    private var borderRadius: CGFloat { iconRadius + inset }
    /// The gap between the icon and its ring. Small on purpose: at 6 the border read as
    /// a box the icon was floating inside rather than as the icon's own outline, which
    /// is what made the icons look shrunken.
    private var inset: CGFloat { 3 }

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
            // No clip on the icon: Apple draws Label(token) with its own bleed, and
            // clipping it to the frame shaved the top edge off.
            .frame(width: size, height: size)
            .overlay {
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: size * 0.32, weight: .semibold))
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
            .overlay(alignment: .bottom) {
                captionLabel(at: date)
                    .fixedSize()
                    .offset(y: 20)
            }
            .padding(.bottom, caption == .none ? 0 : 20)
    }

    @ViewBuilder
    private var icon: some View {
        if let token {
            Label(token)
                .labelStyle(.iconOnly)
                .id(token)
        } else {
            RoundedRectangle(cornerRadius: iconRadius, style: .continuous)
                .fill(LocktyColors.elevatedBackground)
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
