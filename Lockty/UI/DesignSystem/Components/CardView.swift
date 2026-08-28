import SwiftUI

struct CardView<Content: View>: View {
    let radius: CGFloat
    let padding: CGFloat
    let interactive: Bool
    let height: CGFloat?
    let expandsHorizontally: Bool
    let content: Content

    init(
        radius: CGFloat = LocktyRadius.medium,
        padding: CGFloat = LocktySpacing.md,
        interactive: Bool = false,
        height: CGFloat? = nil,
        expandsHorizontally: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.radius = radius
        self.padding = padding
        self.interactive = interactive
        self.height = height
        self.expandsHorizontally = expandsHorizontally
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(
                maxWidth: expandsHorizontally ? .infinity : nil,
                minHeight: height,
                maxHeight: height,
                alignment: .leading
            )
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.black.opacity(0.03), lineWidth: 1)
            }
    }
}
