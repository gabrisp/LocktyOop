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
    func locktyImperfectBorder<S: InsettableShape>(
        _ shape: S,
        tint: Color = .white,
        lineWidth: CGFloat = 1
    ) -> some View {
        overlay {
            shape
                .strokeBorder(
                    AngularGradient(
                        stops: LocktyImperfectBorder.stops(tint: tint),
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
    static func stops(tint: Color) -> [Gradient.Stop] {
        [
            .init(color: tint.opacity(0.26), location: 0.00),
            .init(color: tint.opacity(0.04), location: 0.09),
            .init(color: tint.opacity(0.19), location: 0.17),
            .init(color: tint.opacity(0.00), location: 0.28),
            .init(color: tint.opacity(0.22), location: 0.36),
            .init(color: tint.opacity(0.08), location: 0.44),
            .init(color: tint.opacity(0.30), location: 0.55),
            .init(color: tint.opacity(0.02), location: 0.64),
            .init(color: tint.opacity(0.17), location: 0.72),
            .init(color: tint.opacity(0.00), location: 0.83),
            .init(color: tint.opacity(0.24), location: 0.92),
            .init(color: tint.opacity(0.26), location: 1.00)
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
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background(shape.fill(LocktyColors.ink(0.055)))
            .locktyImperfectBorder(shape)
    }
}
