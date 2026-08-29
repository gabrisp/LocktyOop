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
    @Environment(\.colorScheme) private var colorScheme

    private var auraColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.03)
            : Color.black.opacity(0.03)
    }

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
