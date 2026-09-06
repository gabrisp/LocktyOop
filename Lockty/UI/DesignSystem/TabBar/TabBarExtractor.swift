import SwiftUI
import UIKit

/// Reaches the real `UITabBar` behind SwiftUI's tab view.
///
/// For one thing only: turning the plus into a cross while its panel is open. The button
/// is a system tab item -- that is what makes it sit in the bar and behave like one -- and
/// SwiftUI offers no handle on the image inside it, so the rotation has to be applied to
/// the view UIKit is actually drawing.
///
/// It fails quietly. If the hierarchy is not what it expects, nothing calls back and the
/// plus simply does not turn; nothing else depends on this.
struct TabBarExtractor: UIViewRepresentable {
    var result: (UITabBar) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        DispatchQueue.main.async {
            if let controller = view.superview?.superview?.subviews.last?.subviews.first?.next as? UITabBarController {
                result(controller.tabBar)
            }
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

extension UIView {
    /// Every subview of a type, however deep.
    func subviews<T: UIView>(type: T.Type) -> [T] {
        subviews.compactMap { $0 as? T } + subviews.flatMap { $0.subviews(type: type) }
    }
}

