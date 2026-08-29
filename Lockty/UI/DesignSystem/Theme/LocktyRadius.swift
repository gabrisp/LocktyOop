import CoreGraphics
import Foundation

enum LocktyRadius {
    static let small: CGFloat = 12
    static let medium: CGFloat = 52
    static let large: CGFloat = 20
    static let extraLarge: CGFloat = 28

    /// The proportion the full-width usage card's corner takes of its shorter side.
    ///
    /// Every card is rounded to this same proportion so the curvature reads identically
    /// whatever the card's size. A fixed radius cannot do that: 52pt is a soft corner on
    /// a 360pt-wide card and very nearly a pill on a 150pt tile.
    private static let cardCornerRatio: CGFloat = 52 / 360

    /// The corner radius a card of this size should have.
    ///
    /// Driven by the shorter side, because that is the one the corner has to fit inside
    /// -- a wide short card and a narrow tall one then end up looking equally round.
    static func card(for size: CGSize) -> CGFloat {
        let shorterSide = min(size.width, size.height)
        guard shorterSide > 0 else { return medium }
        return min(max(shorterSide * cardCornerRatio, small), medium)
    }
}
