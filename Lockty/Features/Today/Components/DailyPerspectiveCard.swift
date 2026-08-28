import SwiftUI

struct DailyPerspectiveStackSection: View {
    let perspectives: [DailyPerspective]
    let onDismiss: (DailyPerspective) -> Void

    private var visiblePerspectives: [DailyPerspective] {
        Array(perspectives.prefix(3))
    }

    private var stackHeight: CGFloat {
        visiblePerspectives.isEmpty ? 0 : 152 + CGFloat(max(visiblePerspectives.count - 1, 0)) * 12
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LocktySpacing.sm) {
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
            .frame(height: stackHeight, alignment: .top)
        }
        .frame(maxHeight: visiblePerspectives.isEmpty ? 0 : stackHeight + 22, alignment: .top)
        // Clip vertically so the section can collapse to zero height cleanly, but not
        // horizontally — a plain .clipped() sheared the card mid-swipe as it flew out.
        .clipShape(VerticalOnlyClip())
        .opacity(visiblePerspectives.isEmpty ? 0 : 1)
        .animation(.smooth(duration: 0.3), value: visiblePerspectives.map(\.id))
    }
}

/// Clips top/bottom only, leaving horizontal overflow visible.
private struct VerticalOnlyClip: Shape {
    func path(in rect: CGRect) -> Path {
        Path(rect.insetBy(dx: -1_000, dy: 0))
    }
}

private struct DismissibleDailyPerspectiveCard: View {
    let perspective: DailyPerspective
    let isTopCard: Bool
    let onDismiss: () -> Void

    @State private var dragOffsetX: CGFloat = 0
    @State private var isDismissing = false

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
        .offset(x: dragOffsetX)
        // Pivot from below the card so the swipe reads as a flick rather than a
        // spin about the middle; the divisor is what makes the tilt legible while
        // dragging (~7 degrees by the dismiss threshold, ~30 on the way out).
        .rotationEffect(.degrees(Double(dragOffsetX / 14)), anchor: .bottom)
        .opacity(isDismissing ? 0 : 1)
        .gesture(isTopCard ? dragGesture : nil)
        .animation(.smooth(duration: 0.26), value: isDismissing)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .local)
            .onChanged { value in
                dragOffsetX = value.translation.width
            }
            .onEnded { value in
                let translation = value.translation.width
                let predicted = value.predictedEndTranslation.width
                let shouldDismiss = abs(translation) > threshold || abs(predicted) > 160

                guard shouldDismiss else {
                    withAnimation(.smooth(duration: 0.24)) {
                        dragOffsetX = 0
                    }
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
