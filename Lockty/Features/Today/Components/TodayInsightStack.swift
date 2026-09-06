import SwiftUI

/// The day's insights, as one stack rather than a column of cards.
///
/// The same shape the perspectives stack had, and for the same reason: three notices in a
/// row is a feed at the top of the screen, where a stack is one notice with more behind
/// it. You read the top one, throw it away, and the next comes forward -- so the section
/// takes the room of a single card however much it has to say.
///
/// Dismissals last as long as the screen does. These are readings of today, not messages:
/// there is nothing to mark as read, and one thrown away in the morning is worth showing
/// again tomorrow when it is about a different day.
struct TodayInsightStack: View {
    let insights: [TodayInsight]

    @State private var dismissed: Set<String> = []
    @State private var stackHeight: CGFloat = 0

    private var visible: [TodayInsight] {
        Array(insights.filter { !dismissed.contains($0.id) }.prefix(3))
    }

    /// How far the cards behind the top one peek out.
    private var peekInset: CGFloat {
        CGFloat(max(visible.count - 1, 0)) * 12
    }

    var body: some View {
        // A reader purely for a hard width clamp: `maxWidth: .infinity` can only expand,
        // so a card whose content wants more room than the column has would report that
        // width up to the scroll view and let the whole screen scroll sideways. The
        // height cannot come from the reader for the same reason, so it is measured off
        // the content and fed back.
        GeometryReader { proxy in
            cards
                .frame(width: proxy.size.width, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { newValue in
                    stackHeight = newValue
                }
        }
        .frame(height: visible.isEmpty ? 0 : stackHeight + peekInset)
        // The top card slides right off the screen, so the clip has to be at the screen's
        // edge rather than the column's -- inset outwards by the page gutter, as a clip
        // shape so it does not change the layout width.
        .clipShape(Rectangle().inset(by: -LocktySpacing.tabInset))
        .animation(.smooth(duration: 0.3), value: visible.map(\.id))
    }

    private var cards: some View {
        ZStack(alignment: .top) {
            ForEach(Array(visible.enumerated().reversed()), id: \.element.id) { index, insight in
                DismissibleInsightCard(insight: insight, isTopCard: index == 0) {
                    _ = dismissed.insert(insight.id)
                }
                .scaleEffect(index == 0 ? 1 : 1 - CGFloat(index) * 0.025, anchor: .top)
                .offset(y: CGFloat(index) * 12)
                .opacity(index == 0 ? 1 : 0.82 - CGFloat(index) * 0.14)
                .allowsHitTesting(index == 0)
                .zIndex(Double(visible.count - index))
            }
        }
    }
}

private struct DismissibleInsightCard: View {
    let insight: TodayInsight
    let isTopCard: Bool
    let onDismiss: () -> Void

    /// How far the finger has taken the card.
    ///
    /// A gesture state, not plain state, and that is the fix for the card that stuck: a
    /// `simultaneousGesture` running alongside a scroll view can be cancelled outright --
    /// the scroll claims the touch and `onEnded` never arrives -- which left the offset
    /// wherever it had got to, with the card sitting half off the screen and no way back.
    /// SwiftUI resets a gesture state on its own when that happens.
    @GestureState private var dragTranslation: CGFloat = 0
    /// Where the card flies to once it has actually been let go. This one has to survive
    /// the gesture ending, so it is real state.
    @State private var flyOutOffset: CGFloat = 0
    @State private var isDismissing = false
    /// Tracks crossing the dismiss threshold, so the tick fires once per crossing rather
    /// than on every update past it.
    @State private var isPastThreshold = false
    /// The card's measured size, so the lit rim follows its actual corner rather than a
    /// guess at it -- `CardView` rounds itself in proportion to how big it turns out.
    @State private var size: CGSize = .zero

    @Environment(\.colorScheme) private var colorScheme

    private let threshold: CGFloat = 92

    /// How far into the gesture the card is, 0 to 1. The rim reads this.
    private var dragProgress: CGFloat {
        min(abs(dragTranslation) / threshold, 1)
    }

    private var tint: Color {
        switch insight.tone {
        case .good: LocktyColors.productive
        case .neutral: LocktyColors.neutral
        case .warning: LocktyColors.unproductive
        }
    }

    var body: some View {
        TodayInsightCard(insight: insight)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            // The rim lights as the card is pulled, and goes white for an instant as it
            // leaves. Dragging something away should tell you where the line is before
            // you cross it -- the card used to slide with nothing changing, so the only
            // way to find the threshold was to guess and let go.
            .overlay { rim }
            // A straight slide. The card must not rotate on the way out: it is a line of
            // text about your day, not a card in a game.
            .offset(x: isDismissing ? flyOutOffset : dragTranslation)
            .opacity(isDismissing ? 0 : 1)
            .animation(.smooth(duration: 0.26).delay(0.06), value: isDismissing)
            // simultaneousGesture, not gesture: an exclusive `.gesture` loses to the
            // enclosing vertical scroll view, so the card barely follows the finger.
            // Running alongside it and only tracking horizontally-dominant drags leaves
            // scrolling intact.
            .simultaneousGesture(isTopCard ? dragGesture : nil)
            .sensoryFeedback(.impact(weight: .light), trigger: isPastThreshold) { _, new in new }
            .sensoryFeedback(.impact(weight: .medium), trigger: isDismissing) { _, new in new }
    }

    /// The lit edge. The same construction the score pills use: a blurred copy of the
    /// stroke under a crisp one, added on a dark ground and laid down on a pale one.
    private var rim: some View {
        let shape = RoundedRectangle(
            cornerRadius: size == .zero ? LocktyRadius.medium : LocktyRadius.card(for: size),
            style: .continuous
        )
        let isDark = colorScheme == .dark
        // Full white at the moment of release: a flash, and then it is gone.
        let colour = isDismissing ? Color.white : tint
        let strength = isDismissing ? 1 : dragProgress

        return ZStack {
            shape
                .stroke(colour, lineWidth: isDismissing ? 2 : 1.5)
                .blur(radius: isDismissing ? 9 : 5)
                .opacity(strength * (isDark ? 0.9 : 0.5))
                .blendMode(isDark ? .plusLighter : .normal)

            shape
                .stroke(colour, lineWidth: isDismissing ? 2 : 1.5)
                .opacity(strength)
        }
        .allowsHitTesting(false)
        .animation(.smooth(duration: 0.18), value: isDismissing)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .local)
            // `updating` rather than `onChanged`: it is the half of the gesture that
            // undoes itself. A cancelled drag snaps back on its own instead of leaving
            // the card where the finger left it.
            .updating($dragTranslation) { value, state, transaction in
                // Horizontally-dominant drags only, so a vertical scroll over the card
                // does not drag it sideways.
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                state = value.translation.width
                transaction.animation = nil
            }
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let past = abs(value.translation.width) > threshold
                if past != isPastThreshold { isPastThreshold = past }
            }
            .onEnded { value in
                let translation = value.translation.width

                // Only a drag this card actually tracked can dismiss it; otherwise a
                // vertical flick over it would throw it away.
                guard abs(translation) > abs(value.translation.height) else {
                    isPastThreshold = false
                    return
                }

                let predicted = value.predictedEndTranslation.width
                guard abs(translation) > threshold || abs(predicted) > 160 else {
                    isPastThreshold = false
                    return
                }

                let direction: CGFloat = translation == 0
                    ? (predicted >= 0 ? 1 : -1)
                    : (translation >= 0 ? 1 : -1)

                // The flash first, on its own beat, then the card leaves under it. The
                // fly-out starts from where the finger left it, so the card carries on
                // rather than jumping back to nothing and setting off again.
                flyOutOffset = translation
                isDismissing = true
                withAnimation(.smooth(duration: 0.26).delay(0.06)) {
                    flyOutOffset = direction * 420
                }

                // The fly-out is allowed to play before the card leaves the stack.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) { onDismiss() }
            }
    }
}
