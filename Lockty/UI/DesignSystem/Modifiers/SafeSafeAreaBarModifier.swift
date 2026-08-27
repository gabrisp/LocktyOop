import SwiftUI

extension View {
    @ViewBuilder
    func safeSafeAreaBar<BarContent: View>(
        edge: VerticalEdge,
        alignment: HorizontalAlignment = .center,
        spacing: CGFloat? = nil,
        @ViewBuilder content: () -> BarContent
    ) -> some View {
        if #available(iOS 26.0, *) {
            safeAreaBar(
                edge: edge,
                alignment: alignment,
                spacing: spacing,
                content: content
            )
        } else {
            safeAreaInset(
                edge: edge,
                alignment: alignment,
                spacing: spacing,
                content: content
            )
        }
    }
}
