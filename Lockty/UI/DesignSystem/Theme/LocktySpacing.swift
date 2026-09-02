import Foundation

enum LocktySpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32

    /// The horizontal inset inside a card, wherever one holds rows.
    ///
    /// One number for previews and editors alike: they were 12 and 16, so the same row
    /// sat at a different distance from its card depending on which screen you were
    /// reading it on. This is a touch above the tighter of the two -- the wider one had
    /// the rows floating away from the edge that is supposed to hold them.
    static let cardInset: CGFloat = 14

    /// The horizontal inset of a screen's content: how far a card sits from the edge of
    /// the sheet, on every screen that has one.
    ///
    /// It was nominally `lg` everywhere, but the preview screens padded themselves and
    /// then got padded again by the block that held them, so reading a routine put its
    /// cards at 32 while editing the same routine put them at 16 -- the two halves of one
    /// sheet, laid out to different margins. A single number, a hair over the narrower of
    /// the two, since 16 had the hold button running close to the edge.
    static let screenInset: CGFloat = 18
}
