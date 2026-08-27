import SwiftUI

struct ScreenBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background {
                LocktyColors.secondaryDarkModeBg
                    .ignoresSafeArea()
            }
    }
}

extension View {
    func locktyScreenBackground() -> some View {
        modifier(ScreenBackgroundModifier())
    }
}
