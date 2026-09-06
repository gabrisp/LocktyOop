import SwiftUI

extension View {
    /// A panel that rises out of the tab bar, with the screen dimmed behind it.
    ///
    /// Not a sheet. A sheet covers the bar it came from and takes the plus with it, and
    /// this panel is the plus -- it has to stay attached to the button that opened it,
    /// which means living in the tab's own content rather than above everything.
    @ViewBuilder
    func tabOverlay<Content: View>(
        isPresented: Bool,
        @ViewBuilder content: @escaping () -> Content,
        onDismiss: @escaping () -> Void
    ) -> some View {
        modifier(TabOverlayModifier(isPresented: isPresented, viewContent: content, onDismiss: onDismiss))
    }
}

struct TabOverlayModifier<ViewContent: View>: ViewModifier {
    var isPresented: Bool
    /// Held as a closure, not as a built view.
    ///
    /// Every tab carries this modifier, so a stored view would be two whole panels built
    /// on every pass of the shell's body whether or not either is on screen. Called only
    /// inside the branch that shows one.
    var viewContent: () -> ViewContent
    var onDismiss: () -> Void

    /// Attached only while its own tab is on screen.
    ///
    /// Every tab carries the panel, so without this the one behind would draw it too --
    /// and dismissing would leave a copy of it sitting on a screen nobody is looking at.
    @State private var isViewAppearing = false

    /// The card itself, and how it arrives.
    ///
    /// The glass materialises rather than blurring in: the panel is a piece of glass, and
    /// glass appearing has its own transition on 26 -- one that forms the shape and its
    /// refraction together. A blur-replace fades a picture of glass into place, which is
    /// the difference between the material arriving and an image of it arriving.
    @ViewBuilder
    private var panel: some View {
        let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)

        if #available(iOS 26.0, *) {
            viewContent()
                .clipShape(shape)
                .safeGlass(radius: 30, interactive: true)
                .contentShape(shape)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.horizontal, LocktySpacing.systemTabBarInset)
                .padding(.bottom, 10)
                .transition(.blurReplace)
        } else {
            viewContent()
                .clipShape(shape)
                .safeGlass(radius: 30, interactive: true)
                .contentShape(shape)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.horizontal, LocktySpacing.systemTabBarInset)
                .padding(.bottom, 10)
                .transition(.blurReplace)
        }
    }

    func body(content: Content) -> some View {
        content
            // No frame on the content.
            //
            // It was stretched to fill so the overlay had something full-screen to sit in,
            // and that is the tab's whole navigation stack: every screen pushed inside it
            // was then being laid out inside a forced frame rather than against the window,
            // which is why pushing anything after opening the panel came out wrong. The
            // overlay fills on its own account below.
            .overlay {
                if isViewAppearing {
                    LocktyGlassStack {
                        if isPresented {
                            Rectangle()
                                .fill(.black.opacity(0.15))
                                .contentShape(.rect)
                                .onTapGesture(perform: onDismiss)
                                .ignoresSafeArea()
                                .transition(.opacity)
                        }

                        if isPresented {
                            panel
                        }
                    }
                    .allowsHitTesting(isPresented)
                    .animation(.interpolatingSpring(duration: 0.3, bounce: 0, initialVelocity: 0), value: isPresented)
                }
            }
            .onAppear { isViewAppearing = true }
            .onDisappear { isViewAppearing = false }
    }
}

/// A `GlassEffectContainer` where there is one, and a plain stack where there is not.
///
/// The container is what lets pieces of glass inside it know about each other -- it is
/// also what the materialising transition needs around it to form properly.
struct LocktyGlassStack<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer { content }
        } else {
            ZStack { content }
        }
    }
}
