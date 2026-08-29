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

/// Lets a screen pushed inside a dynamic sheet ask for the whole height.
///
/// A pushed screen cannot be measured -- it fills what the stack gives it -- so instead
/// of reporting a height it says it wants all of it, and gives it back when it leaves.
struct LocktySheetExpansion {
    let setExpanded: (Bool) -> Void

    static let none = LocktySheetExpansion { _ in }
}

private struct LocktySheetExpansionKey: EnvironmentKey {
    static let defaultValue = LocktySheetExpansion.none
}

extension EnvironmentValues {
    var locktySheetExpansion: LocktySheetExpansion {
        get { self[LocktySheetExpansionKey.self] }
        set { self[LocktySheetExpansionKey.self] = newValue }
    }
}

private struct LocktySheetExpandedModifier: ViewModifier {
    @Environment(\.locktySheetExpansion) private var expansion

    func body(content: Content) -> some View {
        content
            .onAppear { expansion.setExpanded(true) }
            .onDisappear { expansion.setExpanded(false) }
    }
}

extension View {
    /// For a screen pushed inside a dynamic sheet that needs the full height. The sheet
    /// goes back to measuring when it is popped.
    func locktySheetExpanded() -> some View {
        modifier(LocktySheetExpandedModifier())
    }

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
    /// Which detent is showing. Declared as a selection over a stable set rather than by
    /// swapping the set itself: replacing one .height with another gives no transition to
    /// animate, so the sheet snapped between sizes.
    @State private var selectedDetent: PresentationDetent = .medium
    /// Raised by a pushed screen that needs the whole sheet.
    @State private var isExpandedByChild = false

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
        // No fixedSize anywhere. Forcing the ideal vertical size collapses a
        // NavigationStack to nothing -- it has no ideal height, it takes what it is
        // given -- which is why a sheet built around one came up empty. Height comes
        // only from what the screen inside reports through locktySheetContent().
        content
            .transition(.blurReplace.combined(with: .opacity))
            .id(contentID)
            .animation(animation, value: contentID)
            .onPreferenceChange(LocktySheetContentHeightKey.self) { newValue in
                guard newValue > 0 else { return }
                reportedHeight = newValue
                updateHeight(newValue)
            }
            .environment(
                \.locktySheetExpansion,
                LocktySheetExpansion { expanded in
                    isExpandedByChild = expanded
                }
            )
            .presentationDetents(detents, selection: $selectedDetent)
            .onChange(of: intendedDetent, initial: true) { _, newValue in
                withAnimation(animation) {
                    selectedDetent = newValue
                }
            }
    }

    /// Everything the sheet can be, at once: the height it measured for itself, and
    /// full. Both stay in the set so moving between them is a change of selection.
    private var detents: Set<PresentationDetent> {
        var set: Set<PresentationDetent> = [.large]
        let height = fixedHeight ?? sheetHeight
        set.insert(height == .zero ? .medium : .height(height))
        return set
    }

    private var intendedDetent: PresentationDetent {
        if isExpanded || isExpandedByChild { return .large }
        let height = fixedHeight ?? sheetHeight
        return height == .zero ? .medium : .height(height)
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
