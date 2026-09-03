import SwiftUI

extension View {
    /// A border that is not the same all the way round.
    ///
    /// A single-opacity stroke reads as a drawn outline: perfectly even, perfectly
    /// closed, and obviously mechanical. This one runs an angular gradient round the
    /// perimeter that fades to nothing in places and lifts in others, so the edge catches
    /// light on some sides and disappears on others -- the card looks *lit* rather than
    /// outlined, and no two sides of it agree.
    ///
    /// The stops are fixed, so the border does not shimmer or crawl on redraw. It is a
    /// still object with uneven light on it, not an animation.
    /// The tint defaults to whichever direction the ground allows. White light on a
    /// black card and black shade on a white one are the same edge described twice; a
    /// white rim on a white card is no rim at all, which is what left light mode leaning
    /// on a shadow -- and a shadow is not an edge.
    func locktyImperfectBorder<S: InsettableShape>(
        _ shape: S,
        tint: Color? = nil,
        lineWidth: CGFloat = 1
    ) -> some View {
        modifier(LocktyImperfectBorderModifier(shape: shape, tint: tint, lineWidth: lineWidth))
    }
}

private struct LocktyImperfectBorderModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color?
    let lineWidth: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    private var resolvedTint: Color {
        if let tint { return tint }
        return colorScheme == .dark ? .white : .black
    }

    func body(content: Content) -> some View {
        content.overlay {
            shape
                .strokeBorder(
                    AngularGradient(
                        stops: LocktyImperfectBorder.stops(
                            tint: resolvedTint,
                            // Black on white reads far stronger than white on black at
                            // the same alpha, so the light rim is pulled back rather than
                            // reused.
                            scale: colorScheme == .dark ? 1 : 0.55
                        ),
                        center: .center
                    ),
                    lineWidth: lineWidth
                )
                .allowsHitTesting(false)
        }
    }
}

enum LocktyImperfectBorder {
    /// Where the edge is lit and where it is not.
    ///
    /// Deliberately uneven in both spacing and value: evenly spaced stops of alternating
    /// opacity would read as a dashed line, which is a pattern, and a pattern is the one
    /// thing this is trying not to be.
    static func stops(tint: Color, scale: Double = 1) -> [Gradient.Stop] {
        [
            .init(color: tint.opacity(0.26 * scale), location: 0.00),
            .init(color: tint.opacity(0.04 * scale), location: 0.09),
            .init(color: tint.opacity(0.19 * scale), location: 0.17),
            .init(color: tint.opacity(0.00 * scale), location: 0.28),
            .init(color: tint.opacity(0.22 * scale), location: 0.36),
            .init(color: tint.opacity(0.08 * scale), location: 0.44),
            .init(color: tint.opacity(0.30 * scale), location: 0.55),
            .init(color: tint.opacity(0.02 * scale), location: 0.64),
            .init(color: tint.opacity(0.17 * scale), location: 0.72),
            .init(color: tint.opacity(0.00 * scale), location: 0.83),
            .init(color: tint.opacity(0.24 * scale), location: 0.92),
            .init(color: tint.opacity(0.26 * scale), location: 1.00)
        ]
    }
}

extension View {
    /// A card: the fill and the uneven edge that goes with it.
    ///
    /// The previews reached for the border by hand and the editors did not, so the same
    /// card had a rim on one screen and none on the next. Anything that looks like a card
    /// should say so in one call rather than remember two.
    func locktyCardBackground(cornerRadius: CGFloat) -> some View {
        modifier(LocktyCardBackgroundModifier(cornerRadius: cornerRadius))
    }
}

/// A card: its surface, the uneven edge, and -- on a pale ground -- the shadow that makes
/// it a card rather than a rectangle of a slightly different grey.
///
/// The dark theme needs no shadow: a lighter shape on black is already raised. The light
/// one needs it, because white on light grey is only a card if something says it is
/// sitting above the page.
private struct LocktyCardBackgroundModifier: ViewModifier {
    let cornerRadius: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        return content
            .background {
                shape
                    .fill(LocktyColors.cardSurface)
                    // A lift, not an outline. The rim is what draws the edge now, so
                    // this is only what puts the card above the page.
                    .shadow(
                        color: colorScheme == .dark ? .clear : .black.opacity(0.045),
                        radius: 10,
                        y: 3
                    )
            }
            .locktyImperfectBorder(shape)
    }
}
