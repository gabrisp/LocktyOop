import SwiftUI

extension View {
    /// Blocks the swipe-down dismiss while there is something unsaved.
    ///
    /// It used to also *report* the refused gesture, by standing in front of the sheet's
    /// `UIPresentationController` delegate and forwarding everything it did not handle,
    /// so a swipe could raise the same discard dialog the X raises. That is the only
    /// UIKit surgery in the app, and it sat on the machinery every sheet depends on: the
    /// delegate is found by walking the responder chain to the nearest view controller,
    /// which inside nested sheets is not always the one that owns the presentation, and a
    /// coordinator outliving or predeceasing its neighbours could leave the presentation
    /// pointing at a dead object. It crashed on two separate sheets.
    ///
    /// Answering a refused swipe is worth something. It is not worth this, so the gesture
    /// is simply refused again, and `onAttempt` is kept so the call sites still say what
    /// they would do if SwiftUI ever surfaces the attempt itself.
    func locktyInteractiveDismiss(
        blocked: Bool,
        onAttempt: @escaping () -> Void
    ) -> some View {
        _ = onAttempt
        return interactiveDismissDisabled(blocked)
    }
}
