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
