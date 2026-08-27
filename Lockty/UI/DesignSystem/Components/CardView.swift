import SwiftUI

struct CardView<Content: View>: View {
    let radius: CGFloat
    let padding: CGFloat
    let interactive: Bool
    let height: CGFloat?
    let content: Content

    init(
        radius: CGFloat = LocktyRadius.large,
        padding: CGFloat = LocktySpacing.lg,
        interactive: Bool = false,
        height: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.radius = radius
        self.padding = padding
        self.interactive = interactive
        self.height = height
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(
                maxWidth: .infinity,
                minHeight: height,
                maxHeight: height,
                alignment: .leading
            )
            .safeGlass(radius: radius, interactive: interactive)
    }
}
