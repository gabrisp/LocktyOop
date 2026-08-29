// Unused since the tab bar was replaced by the live-session bottom bar in HomeView.
// Kept commented rather than deleted in case the tabbed layout comes back.
//
//import SwiftUI
//import UIKit
//
//extension View {
//    @ViewBuilder
//    func hideNativeTabBar() -> some View {
//        self
//            .toolbar(.hidden, for: .tabBar)
//            .toolbarVisibility(.hidden, for: .tabBar)
//    }
//}
//
//extension ScrollView {
//    @ViewBuilder
//    func adoptForIGTabBar(_ progress: Binding<CGFloat>) -> some View {
//        self
//            .modifier(IGTabBarViewModifier(progress: progress))
//    }
//}
//
//struct IGStyleTabBar<Value: Hashable>: UIViewRepresentable {
//    @Binding var selection: Value
//    let values: [Value]
//    var symbolImage: (Value, Bool) -> UIImage
//    var onInteraction: () -> Void = {}
//
//    func makeUIView(context: Context) -> CustomSegmentedControl {
//        let images = values.map { symbolImage($0, $0 == selection) }
//        let control = CustomSegmentedControl(items: images)
//        control.selectedSegmentIndex = values.firstIndex(of: selection) ?? 0
//        control.selectedSegmentTintColor = UIColor(Color.gray.opacity(0.25))
//        control.addTarget(
//            context.coordinator,
//            action: #selector(context.coordinator.valueChanged(_:)),
//            for: .valueChanged
//        )
//
//        control.onTouchBegan = onInteraction
//
//        // Removing Background — image-based segments (unlike a text-based control) render their
//        // icon color from the control's own tintColor, so clearing tintColor/using a transparent
//        // background here makes the icons themselves invisible. This hides only the default
//        // segment background/divider images instead, leaving the actual icon UIImageView (always
//        // the last subview) visible.
//        DispatchQueue.main.async {
//            for subview in control.subviews {
//                if subview is UIImageView && subview != control.subviews.last {
//                    subview.alpha = 0
//                }
//            }
//        }
//
//        return control
//    }
//
//    func updateUIView(_ uiView: CustomSegmentedControl, context: Context) {
//        // SwiftUI calls this on every re-render this view participates in (there's no Equatable
//        // fast-path for a plain closure-holding representable), which during scroll is every
//        // single tabBarProgress update — up to 120/sec on ProMotion. Regenerating both segments'
//        // UIImage(systemName:) unconditionally on each of those was pure waste; only touch the
//        // control at all when the selection actually changed.
//        let selectedIndex = values.firstIndex(of: selection) ?? 0
//        guard uiView.selectedSegmentIndex != selectedIndex else { return }
//        uiView.selectedSegmentIndex = selectedIndex
//
//        // Swap each segment's glyph between outline/filled to track the current selection —
//        // UISegmentedControl only auto-retints on selection change, it doesn't swap the glyph.
//        for (index, value) in values.enumerated() {
//            uiView.setImage(symbolImage(value, value == selection), forSegmentAt: index)
//        }
//    }
//
//    /// Custom Sizing!
//    func sizeThatFits(_ proposal: ProposedViewSize, uiView: CustomSegmentedControl, context: Context) -> CGSize? {
//        .init(
//            width: CGFloat(values.count) * 80,
//            height: 50
//        )
//    }
//
//    func makeCoordinator() -> Coordinator {
//        Coordinator(parent: self)
//    }
//
//    class Coordinator: NSObject {
//        var parent: IGStyleTabBar
//        init(parent: IGStyleTabBar) {
//            self.parent = parent
//        }
//
//        @objc
//        func valueChanged(_ sender: UISegmentedControl) {
//            guard parent.values.indices.contains(sender.selectedSegmentIndex) else { return }
//            parent.selection = parent.values[sender.selectedSegmentIndex]
//            parent.onInteraction()
//        }
//    }
//}
//
//class CustomSegmentedControl: UISegmentedControl {
//    var onTouchBegan: (() -> Void)?
//
//    func configureTransparentBackground() {
//        let clearImage = UIImage.clearSegmentBackground
//        setBackgroundImage(clearImage, for: .normal, barMetrics: .default)
//        setBackgroundImage(clearImage, for: .selected, barMetrics: .default)
//        setBackgroundImage(clearImage, for: .highlighted, barMetrics: .default)
//        setDividerImage(clearImage, forLeftSegmentState: .normal, rightSegmentState: .normal, barMetrics: .default)
//        setDividerImage(clearImage, forLeftSegmentState: .selected, rightSegmentState: .normal, barMetrics: .default)
//        setDividerImage(clearImage, forLeftSegmentState: .normal, rightSegmentState: .selected, barMetrics: .default)
//    }
//
//    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
//        super.touchesBegan(touches, with: event)
//        onTouchBegan?()
//    }
//}
//
//private extension UIImage {
//    static var clearSegmentBackground: UIImage {
//        UIGraphicsImageRenderer(size: CGSize(width: 1, height: 32)).image { context in
//            UIColor.clear.setFill()
//            context.fill(CGRect(x: 0, y: 0, width: 1, height: 32))
//        }
//    }
//}
//
//fileprivate struct IGTabBarViewModifier: ViewModifier {
//    /// 0- means expanded
//    /// 1- means minimized
//    @Binding var progress: CGFloat
//    /// View Properties
//    @GestureState private var isDragging: Bool = false
//    @State private var isScrolledUp: Bool?
//    @State private var shiftOffset: CGFloat = 0
//    @State private var scrollOffset: CGFloat = 0
//    @State private var isLargerContent: Bool = false
//    @State private var scrollPhase: ScrollPhase = .idle
//
//    func body(content: Content) -> some View {
//        content
//            /// If you add this modifier, then no need for hide tab bar modifier to be added!
//            .toolbarVisibility(.hidden, for: .tabBar)
//            /// Adjusting Tab Bar Height!
//            .safeAreaPadding(.bottom, 50)
//            .frame(maxWidth: .infinity, maxHeight: .infinity)
//            .contentShape(.rect)
//            .simultaneousGesture(
//                DragGesture(minimumDistance: 0, coordinateSpace: .scrollView)
//                    .updating($isDragging) { _, out, _ in
//                        out = true
//                    }.onEnded { value in
//                        guard scrollPhase != .idle else { return }
//                        /// NOTE: To decrease velocity increase the number from 5 to something higher!
//                        let velocity = -value.velocity.height / 5
//                        let resultOffset = scrollOffset + velocity
//                        let rawProgress = (resultOffset - shiftOffset) / distance
//                        let clampedProgress = max(0, min(1, rawProgress))
//
//                        withAnimation(animation) {
//                            self.progress = resultOffset > (distance / 2) && isLargerContent ? (clampedProgress > 0.5 ? 1 : 0) : 0
//                        }
//
//                        isScrolledUp = nil
//                        /// Adjusting Shift Offset accordingly!
//                        shiftOffset = scrollOffset - (progress * distance)
//                    }
//            )
//            .onScrollPhaseChange({ oldPhase, newPhase in
//                scrollPhase = newPhase
//            })
//            .onScrollGeometryChange(for: CGFloat.self, of: {
//                $0.contentSize.height - $0.containerSize.height
//            }, action: { oldValue, newValue in
//                isLargerContent = newValue > 0
//            })
//            .onScrollGeometryChange(for: CGFloat.self) {
//                $0.contentOffset.y + $0.contentInsets.top
//            } action: { oldValue, newValue in
//                guard isDragging else { return }
//                scrollOffset = newValue
//                let isScrolledUp = oldValue < newValue
//
//                if self.isScrolledUp != isScrolledUp {
//                    self.isScrolledUp = isScrolledUp
//                    /// Store Shift Offset
//                    self.shiftOffset = newValue - (progress * distance)
//                }
//
//                let rawProgress = (newValue - shiftOffset) / distance
//                let clampedProgress = max(0, min(1, rawProgress))
//
//                withAnimation(animation) {
//                    self.progress = clampedProgress
//                }
//            }
//    }
//
//    /// Update these values according to your own needs!
//    private var distance: CGFloat {
//        100
//    }
//
//    private var animation: Animation {
//        .interpolatingSpring(duration: 0.25, bounce: 0, initialVelocity: 0)
//    }
//}
//
