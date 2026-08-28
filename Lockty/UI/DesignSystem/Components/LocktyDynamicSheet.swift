import SwiftUI
import UIKit

struct LocktyDynamicSheet<Content: View>: View {
    let animation: Animation
    let fixedHeight: CGFloat?
    let content: Content

    @State private var sheetHeight: CGFloat = 0

    init(
        animation: Animation = .easeInOut(duration: 0.28),
        fixedHeight: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.animation = animation
        self.fixedHeight = fixedHeight
        self.content = content()
    }

    var body: some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { _, newValue in
                updateHeight(newValue.height)
            }
            .presentationDetents(detents)
    }

    private var detents: Set<PresentationDetent> {
        let height = fixedHeight ?? sheetHeight
        return height == .zero ? [.medium] : [.height(height)]
    }

    private func updateHeight(_ measuredHeight: CGFloat) {
        let resolvedHeight = min(fixedHeight ?? measuredHeight, windowSize.height - 96)
        guard resolvedHeight > 0 else { return }

        if sheetHeight == .zero || fixedHeight != nil {
            sheetHeight = resolvedHeight
        } else {
            withAnimation(animation) {
                sheetHeight = resolvedHeight
            }
        }
    }

    private var windowSize: CGSize {
        if let size = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.bounds.size {
            return size
        }
        return .zero
    }
}
