import SwiftUI

/// A rounded rectangle drawn by hand rather than by a compass.
///
/// A superellipse -- the squircle iOS itself rounds things with -- sampled around its
/// perimeter, each sample nudged in or out by a small fixed amount, then smoothed by
/// running quadratic curves through the midpoints so every sample becomes a control
/// rather than a corner. The outline stays a rounded rectangle and is nowhere exactly
/// one.
///
/// The nudges come from a fixed table, not from a random generator. A border that
/// reshuffled on every redraw would crawl, and one re-seeded per instance would make two
/// identical panels look like different components. It should read as drawn, not as
/// unstable.
struct LocktyImperfectShape: InsettableShape {
    /// How square the outline is. 2 is an ellipse; 4 is close to an iOS squircle; higher
    /// values push the edges flatter and the corners tighter.
    var squareness: Double = 4.4
    /// How far the outline strays, as a fraction of the radius. Small on purpose: past a
    /// couple of percent it stops reading as a hand-drawn edge and starts reading as a
    /// mistake.
    var wobble: CGFloat = 0.02
    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> LocktyImperfectShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    func path(in rect: CGRect) -> Path {
        let bounds = rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard bounds.width > 0, bounds.height > 0 else { return Path() }

        let centre = CGPoint(x: bounds.midX, y: bounds.midY)
        let halfWidth = bounds.width / 2
        let halfHeight = bounds.height / 2
        let exponent = 2 / squareness
        let count = Self.offsets.count

        func point(at index: Int) -> CGPoint {
            let wrapped = ((index % count) + count) % count
            let angle = (Double(wrapped) / Double(count)) * 2 * .pi

            // Parametric superellipse. The signed power is what keeps the edges flat and
            // the corners tight; a plain cos/sin would give an ellipse.
            let cosine = cos(angle)
            let sine = sin(angle)
            let x = CGFloat(copysign(pow(abs(cosine), exponent), cosine))
            let y = CGFloat(copysign(pow(abs(sine), exponent), sine))

            let stray = 1 + wobble * Self.offsets[wrapped]
            return CGPoint(
                x: centre.x + halfWidth * x * stray,
                y: centre.y + halfHeight * y * stray
            )
        }

        func midpoint(_ first: CGPoint, _ second: CGPoint) -> CGPoint {
            CGPoint(x: (first.x + second.x) / 2, y: (first.y + second.y) / 2)
        }

        var path = Path()
        path.move(to: midpoint(point(at: count - 1), point(at: 0)))

        for index in 0..<count {
            path.addQuadCurve(
                to: midpoint(point(at: index), point(at: index + 1)),
                control: point(at: index)
            )
        }

        path.closeSubpath()
        return path
    }

    /// Fixed strays, between -1 and 1, in no particular order so the outline does not
    /// fall into a rhythm.
    private static let offsets: [CGFloat] = [
        0.4, -0.7, 0.2, 0.9, -0.3, 0.6, -0.9, 0.1,
        0.7, -0.4, 0.9, -0.2, 0.3, -0.8, 0.5, 0.0,
        -0.6, 0.8, -0.1, 0.4, -0.9, 0.2, 0.6, -0.5,
        0.9, -0.3, 0.1, 0.7, -0.7, 0.3, -0.2, 0.5
    ]
}
