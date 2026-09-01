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
    /// Driven by width, which is the reference dimension the full-width cards were
    /// designed against. Height still caps the result so a short card cannot end up
    /// with a corner that doesn't fit inside itself.
    static func card(for size: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return medium }
        let proportionalToWidth = size.width * cardCornerRatio
        let maximumThatFits = min(size.width, size.height) / 2
        return min(max(proportionalToWidth, small), medium, maximumThatFits)
    }
}
