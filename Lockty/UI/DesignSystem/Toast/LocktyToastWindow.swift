import SwiftUI
import UIKit

/// A window that only takes the touches its own content is under.
///
/// The toast lives in a window above everything so it can sit over the status bar and
/// survive sheets. That window covers the screen, so without this every tap anywhere
/// would land on it instead of on the app.
///
/// Adapted from Balaji Venkatesh's DynamicIslandToast.
final class LocktyPassThroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hitView = super.hitTest(point, with: event),
              let rootView = rootViewController?.view
        else { return nil }

        // Anything that landed on the root view itself is empty space above the app, so
        // it goes through. Only a hit on an actual subview -- the toast -- is kept.
        for subview in rootView.subviews.reversed() {
            let pointInSubview = subview.convert(point, from: rootView)
            if subview.hitTest(pointInSubview, with: event) != nil {
                return hitView
            }
        }

        return nil
    }
}

/// Hides the status bar while a toast is expanded, so the clock does not sit inside it.
final class LocktyToastHostingController<Content: View>: UIHostingController<Content> {
    var isStatusBarHidden = false {
        didSet { setNeedsStatusBarAppearanceUpdate() }
    }

    override var prefersStatusBarHidden: Bool {
        isStatusBarHidden
    }
}

/// Reaches the window scene, which is the only way to make another window alongside it.
struct LocktyWindowExtractor: UIViewRepresentable {
    var onResolve: (UIWindow) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            onResolve(window)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
