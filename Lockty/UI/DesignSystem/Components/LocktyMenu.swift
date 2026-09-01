import SwiftUI

extension View {
    /// A menu that grows out of the control that opened it.
    ///
    /// Replaces the bare `.popover` everywhere in the app. A plain popover appears beside
    /// its button with no relationship to it -- there is an arrow, and that is all that
    /// says the two belong together. This zooms out of the control itself, so the panel
    /// is visibly the same object opening up.
    ///
    /// The content still travels in a popover underneath, because that is what gives it
    /// dismiss-anywhere and its own sizing. What changes is that the control is a
    /// `matchedTransitionSource` and the panel arrives through a zoom.
    ///
    /// Written as a modifier rather than as a wrapper view on purpose: every one of these
    /// controls is already a styled button where it sits, and a wrapper would have to own
    /// that button and flatten all of them into one look.
    ///
    /// Adapted from Balaji Venkatesh's CustomMenuView.
    func locktyMenu<Content: View>(
        isPresented: Binding<Bool>,
        arrowEdge: Edge? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(
            LocktyMenuModifier(
                isPresented: isPresented,
                arrowEdge: arrowEdge,
                menuContent: content
            )
        )
    }
}

private struct LocktyMenuModifier<MenuContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let arrowEdge: Edge?
    @ViewBuilder var menuContent: () -> MenuContent

    /// One namespace per attachment, so two menus on the same screen zoom from their own
    /// control rather than from whichever registered the shared id last.
    @Namespace private var namespace
    /// Selection feedback when the menu opens, matching every other control in the app.
    @State private var haptics = false

    func body(content: Content) -> some View {
        content
            .matchedTransitionSource(id: Self.sourceID, in: namespace)
            .popover(
                isPresented: $isPresented,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: arrowEdge
            ) {
                LocktyMenuPanel {
                    menuContent()
                }
                .navigationTransition(.zoom(sourceID: Self.sourceID, in: namespace))
            }
            .sensoryFeedback(.selection, trigger: haptics)
            .onChange(of: isPresented) { _, newValue in
                guard newValue else { return }
                haptics.toggle()
            }
    }

    private static var sourceID: String { "lockty.menu" }
}

/// Holds the content back for a beat, then fades it in.
///
/// The zoom animates the panel's frame; its contents would otherwise be fully drawn from
/// the first frame and appear to be stretched into place by it. Letting them arrive just
/// after means the panel opens and *then* fills.
private struct LocktyMenuPanel<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var isVisible = false

    var body: some View {
        content
            .opacity(isVisible ? 1 : 0)
            .task {
                try? await Task.sleep(for: .milliseconds(100))
                withAnimation(.snappy(duration: 0.3, extraBounce: 0)) {
                    isVisible = true
                }
            }
            // Keeps it a popover on iPhone. Without it the system adapts a popover into a
            // sheet at compact width, which is not what any of these are.
            .presentationCompactAdaptation(.popover)
    }
}
