import SwiftUI
import UIKit

extension View {
    /// Blocks the swipe-down dismiss, and says so instead of just refusing.
    ///
    /// `interactiveDismissDisabled` on its own is silent: the sheet rubber-bands back and
    /// nothing explains why, so an editor with unsaved changes looked like a sheet that
    /// had simply stopped working. Swiping down is the same intent as tapping the X, so
    /// it deserves the same answer -- the confirmation that asks whether to discard.
    ///
    /// UIKit knows when the gesture was attempted and refused; SwiftUI does not surface
    /// it, so `onAttempt` is wired to `presentationControllerDidAttemptToDismiss`.
    func locktyInteractiveDismiss(
        blocked: Bool,
        onAttempt: @escaping () -> Void
    ) -> some View {
        interactiveDismissDisabled(blocked)
            .background(
                LocktyDismissAttemptProbe(onAttempt: onAttempt)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            )
    }
}

/// Listens for a refused swipe-down on whichever sheet it is placed in.
private struct LocktyDismissAttemptProbe: UIViewRepresentable {
    let onAttempt: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onAttempt = onAttempt

        // Deferred by one turn: on the pass that creates this view it is not in a window
        // yet, so it has no view controller and no presentation controller to attach to.
        DispatchQueue.main.async {
            guard let presentation = uiView.locktyOwningViewController()?.presentationController else {
                return
            }
            context.coordinator.attach(to: presentation)
        }
    }

    /// Stands in front of SwiftUI's own presentation delegate rather than replacing it.
    ///
    /// SwiftUI installs a delegate of its own and relies on it, so everything this does
    /// not handle is forwarded straight back. Taking the delegate over outright breaks
    /// the sheet's detents and its dismissal.
    final class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate {
        var onAttempt: (() -> Void)?
        private weak var forwarding: UIAdaptivePresentationControllerDelegate?
        private weak var attached: UIPresentationController?

        func attach(to presentation: UIPresentationController) {
            // Already in place. Re-attaching would make this forward to itself, and the
            // first attempted dismiss would recurse until the stack ran out.
            guard presentation.delegate !== self else { return }

            forwarding = presentation.delegate
            attached = presentation
            presentation.delegate = self
        }

        func presentationControllerDidAttemptToDismiss(_ controller: UIPresentationController) {
            onAttempt?()
            forwarding?.presentationControllerDidAttemptToDismiss?(controller)
        }

        override func responds(to aSelector: Selector!) -> Bool {
            if super.responds(to: aSelector) { return true }
            return forwarding?.responds(to: aSelector) ?? false
        }

        override func forwardingTarget(for aSelector: Selector!) -> Any? {
            if forwarding?.responds(to: aSelector) == true { return forwarding }
            return super.forwardingTarget(for: aSelector)
        }

        deinit {
            // Handing the delegate back on the way out, so a sheet that outlives this
            // probe is not left pointing at nothing.
            if let attached, attached.delegate === self {
                attached.delegate = forwarding
            }
        }
    }
}

private extension UIView {
    /// The view controller this view belongs to, found by walking the responder chain.
    func locktyOwningViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let controller = current as? UIViewController { return controller }
            responder = current.next
        }
        return nil
    }
}
