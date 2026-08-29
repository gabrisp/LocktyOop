import SwiftUI
import UIKit

/// Height reported from inside a dynamic sheet.
///
/// A NavigationStack fills whatever it is offered and never reports what is in it, so
/// measuring the sheet's own content view gives back the sheet's height and the detent
/// can never settle. The screen inside marks itself instead and the height travels up as
/// a preference, which crosses the stack that geometry cannot.
struct LocktySheetContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        // Last non-zero wins rather than the tallest: with a stack, a screen that was
        // pushed and popped would otherwise hold the sheet open at its height forever.
        let next = nextValue()
        if next > 0 { value = next }
    }
}

extension View {
    /// Marks the view whose height the enclosing `LocktyDynamicSheet` should take.
    ///
    /// Put it on the content of each screen inside the sheet -- inside any
    /// NavigationStack, not around it.
    func locktySheetContent() -> some View {
        background {
            GeometryReader { proxy in
                Color.clear
                    .preference(key: LocktySheetContentHeightKey.self, value: proxy.size.height)
            }
        }
    }
}

struct LocktyDynamicSheet<Content: View>: View {
    let animation: Animation
    let fixedHeight: CGFloat?
    /// Identity of what is on screen. When it changes the content crossfades through a
    /// blur while the sheet resizes, so growing to fit a newly opened section reads as
    /// one movement rather than a jump followed by a redraw.
    let contentID: AnyHashable?
    /// Takes the whole screen instead of measuring. For content that is a screen in its
    /// own right -- a picker with its own list -- where sizing to it would just mean
    /// full height with an extra layout pass first.
    let isExpanded: Bool
    let content: Content

    @State private var sheetHeight: CGFloat = 0
    /// Height a screen inside reported for itself, zero when none did.
    @State private var reportedHeight: CGFloat = 0

    init(
        animation: Animation = .easeInOut(duration: 0.28),
        fixedHeight: CGFloat? = nil,
        contentID: AnyHashable? = nil,
        isExpanded: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.animation = animation
        self.fixedHeight = fixedHeight
        self.contentID = contentID
        self.isExpanded = isExpanded
        self.content = content()
    }

    var body: some View {
        content
            .transition(.blurReplace.combined(with: .opacity))
            .id(contentID)
            .animation(animation, value: contentID)
            // Only when nothing inside is reporting its own height: a plain content view
            // can be measured directly, a NavigationStack cannot.
            .fixedSize(horizontal: false, vertical: reportedHeight == 0)
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { _, newValue in
                guard reportedHeight == 0 else { return }
                updateHeight(newValue.height)
            }
            .onPreferenceChange(LocktySheetContentHeightKey.self) { newValue in
                guard newValue > 0 else { return }
                reportedHeight = newValue
                updateHeight(newValue)
            }
            .presentationDetents(detents)
    }

    private var detents: Set<PresentationDetent> {
        if isExpanded { return [.large] }
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
