import SwiftUI

struct GlassContainerCompat<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    init(spacing: CGFloat = LocktySpacing.md, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}
