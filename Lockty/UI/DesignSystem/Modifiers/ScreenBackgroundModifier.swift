import SwiftUI

struct ScreenBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background {
                LocktyScreenBackground()
                    .ignoresSafeArea()
            }
    }
}

extension View {
    func locktyScreenBackground() -> some View {
        modifier(ScreenBackgroundModifier())
    }
}

struct LocktyScreenBackground: View {
    /// The blooms behind every screen.
    ///
    /// Not `ink`: on a light page that is black at 2%, which is a smudge rather than a
    /// glow -- and the point of these is light, not shade. Light mode gets white blooms
    /// on the grey ground, which is the same gesture the dark one makes and the only one
    /// that reads as a light source rather than as dirt.
    private let auraColor = LocktyColors.screenAura

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let maxDimension = max(size.width, size.height)

            ZStack {
                LocktyColors.background

                circle(size: maxDimension * 0.92)
                    .offset(x: -maxDimension * 0.42, y: -maxDimension * 0.30)

                circle(size: maxDimension * 0.72)
                    .offset(x: maxDimension * 0.34, y: -maxDimension * 0.20)

                circle(size: maxDimension * 0.84)
                    .offset(x: maxDimension * 0.22, y: maxDimension * 0.26)

                circle(size: maxDimension * 0.56)
                    .offset(x: -maxDimension * 0.18, y: maxDimension * 0.48)

                circle(size: maxDimension * 0.40)
                    .offset(x: maxDimension * 0.46, y: maxDimension * 0.56)
            }
            .frame(width: size.width, height: size.height)
        }
    }

    private func circle(size: CGFloat) -> some View {
        Circle()
            .fill(auraColor)
            .frame(width: size, height: size)
            .blur(radius: size * 0.08)
    }
}
