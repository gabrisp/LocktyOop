import SwiftUI

struct DailyPerspectiveStackSection: View {
    let perspectives: [DailyPerspective]
    let onDismiss: (DailyPerspective) -> Void

    private var visiblePerspectives: [DailyPerspective] {
        Array(perspectives.prefix(3))
    }

    /// Vertical inset the stacked cards behind the top one peek out by.
    private var peekInset: CGFloat {
        CGFloat(max(visiblePerspectives.count - 1, 0)) * 12
    }

    var body: some View {
        // Height comes from the tallest card (it used to be hardcoded to 152, so longer
        // copy overflowed) and the section collapses on its own once all are dismissed.
        // The card slides up to 420pt sideways on dismissal, so the section is pinned to
        // the container width and clipped — without that the fly-out renders far outside
        // these bounds. (An earlier version skipped clipping to keep a rotation visible;
        // there is no rotation any more, so straightforward clipping is correct here.)
        ZStack(alignment: .top) {
            ForEach(Array(visiblePerspectives.enumerated().reversed()), id: \.element.id) { index, perspective in
                DismissibleDailyPerspectiveCard(
                    perspective: perspective,
                    isTopCard: index == 0,
                    onDismiss: { onDismiss(perspective) }
                )
                .scaleEffect(index == 0 ? 1 : 1 - CGFloat(index) * 0.025, anchor: .top)
                .offset(y: CGFloat(index) * 12)
                .opacity(index == 0 ? 1 : 0.82 - CGFloat(index) * 0.14)
                .allowsHitTesting(index == 0)
                .zIndex(Double(visiblePerspectives.count - index))
            }
        }
        // Padding lives inside the clip so cards sit inset from the screen edge while
        // the fly-out still runs all the way to that edge before being clipped.
        .padding(.horizontal, LocktySpacing.md)
        .padding(.bottom, peekInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .animation(.smooth(duration: 0.3), value: visiblePerspectives.map(\.id))
    }
}

private struct DismissibleDailyPerspectiveCard: View {
    let perspective: DailyPerspective
    let isTopCard: Bool
    let onDismiss: () -> Void

    @State private var dragOffsetX: CGFloat = 0
    @State private var isDismissing = false
    /// Tracks crossing the dismiss threshold so the haptic fires once per crossing
    /// (in both directions) rather than on every drag update past it.
    @State private var isPastThreshold = false

    private var threshold: CGFloat {
        92
    }

    private var toneColor: Color {
        switch perspective.tone {
        case .excellent:
            LocktyColors.productive
        case .focused:
            LocktyColors.warning
        case .balanced:
            LocktyColors.neutral
        case .distracted, .highDistraction:
            LocktyColors.unproductive
        }
    }

    var body: some View {
        CardView(radius: LocktyRadius.large, padding: LocktySpacing.lg) {
            VStack(alignment: .leading, spacing: LocktySpacing.md) {
                Capsule()
                    .fill(toneColor)
                    .frame(width: 36, height: 4)

                Text(perspective.title)
                    .font(.system(.title3, design: .default, weight: .semibold))
                    .foregroundStyle(LocktyColors.primaryText)

                Text(perspective.body)
                    .font(LocktyTypography.body)
                    .foregroundStyle(LocktyColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // Straight horizontal slide only — the card must not rotate as it's dismissed.
        .offset(x: dragOffsetX)
        .opacity(isDismissing ? 0 : 1)
        // simultaneousGesture, not gesture: the enclosing vertical ScrollView wins an
        // exclusive .gesture(), so onChanged barely fires and the card doesn't follow
        // the finger. Running alongside the scroll and only tracking
        // horizontally-dominant drags keeps vertical scrolling intact.
        .simultaneousGesture(isTopCard ? dragGesture : nil)
        .animation(.smooth(duration: 0.26), value: isDismissing)
        // A light tick as the swipe passes the point where releasing would dismiss,
        // and a firmer one when it actually goes.
        .sensoryFeedback(.impact(weight: .light), trigger: isPastThreshold) { _, new in new }
        .sensoryFeedback(.impact(weight: .medium), trigger: isDismissing) { _, new in new }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .local)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                dragOffsetX = value.translation.width

                let past = abs(dragOffsetX) > threshold
                if past != isPastThreshold {
                    isPastThreshold = past
                }
            }
            .onEnded { value in
                // Only a drag we actually tracked horizontally can dismiss; otherwise a
                // vertical scroll flick over the card would throw it away.
                guard dragOffsetX != 0 else { return }

                let translation = value.translation.width
                let predicted = value.predictedEndTranslation.width
                let shouldDismiss = abs(translation) > threshold || abs(predicted) > 160

                guard shouldDismiss else {
                    withAnimation(.smooth(duration: 0.24)) {
                        dragOffsetX = 0
                    }
                    isPastThreshold = false
                    return
                }

                let direction: CGFloat = translation == 0 ? (predicted >= 0 ? 1 : -1) : (translation >= 0 ? 1 : -1)
                withAnimation(.smooth(duration: 0.26)) {
                    dragOffsetX = direction * 420
                    isDismissing = true
                }

                // Let the fly-out actually play before the card is pulled from the
                // stack — removing it mid-animation cut the rotation off early.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
                    onDismiss()
                }
            }
    }
}
