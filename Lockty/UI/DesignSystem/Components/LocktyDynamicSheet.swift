import Combine
import SwiftUI
import UIKit

enum LocktyDynamicSheetSize: Hashable {
    case fit
    case small
    case medium
    case large
}

@MainActor
final class LocktyDynamicSheetChromeController: ObservableObject {
    struct Configuration {
        var ownerID: UUID
        var transitionID: AnyHashable
        /// Whatever the screen wants in the middle -- a title, or an icon and a name.
        /// It is a view, not a string, because it is the screen's to decide.
        var center: AnyView
        var leading: AnyView
        var trailing: AnyView
    }

    @Published private(set) var configuration: Configuration?
    @Published private(set) var sizes: [LocktyDynamicSheetSize]?
    private var sizesOwnerID: UUID?

    func set(
        ownerID: UUID,
        transitionID: AnyHashable,
        center: AnyView,
        leading: AnyView,
        trailing: AnyView
    ) {
        configuration = Configuration(
            ownerID: ownerID,
            transitionID: transitionID,
            center: center,
            leading: leading,
            trailing: trailing
        )
    }

    func clear(ownerID: UUID) {
        guard configuration?.ownerID == ownerID else { return }
        configuration = nil
    }

    func setSizes(
        ownerID: UUID,
        sizes: [LocktyDynamicSheetSize]
    ) {
        sizesOwnerID = ownerID
        self.sizes = sizes
    }

    func clearSizes(ownerID: UUID) {
        guard sizesOwnerID == ownerID else { return }
        sizes = nil
        sizesOwnerID = nil
    }
}

private struct LocktyDynamicSheetChromeControllerKey: EnvironmentKey {
    static let defaultValue: LocktyDynamicSheetChromeController? = nil
}

extension EnvironmentValues {
    var locktyDynamicSheetChromeController: LocktyDynamicSheetChromeController? {
        get { self[LocktyDynamicSheetChromeControllerKey.self] }
        set { self[LocktyDynamicSheetChromeControllerKey.self] = newValue }
    }
}

private struct LocktyDynamicSheetChromeModifier<Center: View, Leading: View, Trailing: View>: ViewModifier {
    @Environment(\.locktyDynamicSheetChromeController) private var chromeController

    /// @State, not a stored let. A ViewModifier is a struct rebuilt on every body pass,
    /// so a plain `let ownerID = UUID()` is a different id each time -- what registered
    /// and what tries to unregister never match, and nothing is ever cleared.
    @State private var ownerID = UUID()
    let updateID: AnyHashable
    let center: Center
    let leading: Leading
    let trailing: Trailing

    func body(content: Content) -> some View {
        content
            .onAppear(perform: apply)
            .onChange(of: updateID, initial: true) { _, _ in
                apply()
            }
            .onDisappear {
                chromeController?.clear(ownerID: ownerID)
            }
    }

    private func apply() {
        chromeController?.set(
            ownerID: ownerID,
            transitionID: updateID,
            center: AnyView(center),
            leading: AnyView(leading),
            trailing: AnyView(trailing)
        )
    }
}

private struct LocktyDynamicSheetSizesModifier: ViewModifier {
    @Environment(\.locktyDynamicSheetChromeController) private var chromeController

    /// Same reason as the chrome modifier: a regenerated id meant clearSizes never
    /// matched, so what a screen registered was never taken back.
    @State private var ownerID = UUID()
    let sizes: [LocktyDynamicSheetSize]

    /// A screen asking for one size gets given that height, and the sheet goes on
    /// measuring exactly as it does for everything else.
    ///
    /// The sheet used to stop measuring and let this screen fill instead, and that is
    /// what broke reading the height on the way back: the content's layout mode changed
    /// underneath it, so the reading after returning was of something laid out to fill
    /// rather than of the content. Handing over a height keeps every screen measurable
    /// and every change height-to-height.
    /// The height to give the *content*, which is not the height the sheet ends up.
    ///
    /// The bar is a safe area inset added on top of whatever this returns, so its own
    /// height has to come out of the number here. It did not, so a screen asking for
    /// `.large` produced a sheet of `availableHeight + barHeight` -- taller than a sheet
    /// can be. The content was pushed up to fit and the bar went off the top edge with
    /// it, which is the bar appearing to stick out above the sheet.
    private var explicitHeight: CGFloat? {
        guard sizes.count == 1, let only = sizes.first else { return nil }

        let contentHeight: CGFloat
        switch only {
        case .fit: return nil
        case .small: contentHeight = availableHeight * 0.33
        case .medium: contentHeight = availableHeight * 0.5
        case .large: contentHeight = availableHeight
        }

        // Never below zero, however small the window reports itself as during a scene
        // transition -- a negative frame height is a layout the sheet cannot recover from.
        return max(contentHeight - locktyDynamicSheetBarHeight, 0)
    }

    /// What the finished sheet should measure, not what the window is. Asking for the
    /// window's full height made the content taller than the sheet it produced.
    private var availableHeight: CGFloat {
         windowHeight - 110
    }

    private var windowHeight: CGFloat {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.bounds.size.height ?? 0
    }

    func body(content: Content) -> some View {
        content
            .frame(height: explicitHeight)
            // Registered only when there is more than one size, which is the one case
            // the sheet has to know about: several sizes means draggable.
            .onAppear {
                guard sizes.count > 1 else { return }
                chromeController?.setSizes(ownerID: ownerID, sizes: sizes)
            }
            .onDisappear {
                chromeController?.clearSizes(ownerID: ownerID)
            }
    }
}

extension View {
    /// The sheet's bar for this screen: a button, whatever the screen puts in the
    /// middle, and a button.
    func locktyDynamicSheetChrome<Center: View, Leading: View, Trailing: View>(
        id: AnyHashable,
        @ViewBuilder center: () -> Center,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        modifier(
            LocktyDynamicSheetChromeModifier(
                updateID: id,
                center: center(),
                leading: leading(),
                trailing: trailing()
            )
        )
    }

    func locktyDynamicSheetSizes(_ sizes: [LocktyDynamicSheetSize]) -> some View {
        modifier(LocktyDynamicSheetSizesModifier(sizes: sizes))
    }
}

/// The bar's parts, and its height derived from them.
///
/// Derived, not written down twice: the height the inset reserves and the padding the
/// bar draws were two separate numbers, and every time one moved the other did not, so
/// the bar sat above the space kept for it.
private let locktyDynamicSheetBarTopPadding: CGFloat = LocktySpacing.lg
private let locktyDynamicSheetBarBottomPadding: CGFloat = 4
private let locktyDynamicSheetBarButtonSize: CGFloat = 44
private let locktyDynamicSheetBarHeight: CGFloat =
    locktyDynamicSheetBarTopPadding + locktyDynamicSheetBarButtonSize + locktyDynamicSheetBarBottomPadding

/// A sheet that is exactly as tall as what is in it.
///
/// It measures and nothing else. Swapping between screens, and the transition that goes
/// with it, belongs to the content -- a ZStack with a switch, each branch in a
/// geometryGroup -- because the sheet resizing and the content changing have to be one
/// movement, and only the content knows when it is changing.
struct LocktyDynamicSheet<Content: View>: View {
    var animation: Animation = .snappy(duration: 0.3, extraBounce: 0)
    @ViewBuilder var content: Content

    @State private var sheetHeight: CGFloat = 0
    /// iOS 17 lays a sheet out before it is on screen and the first measurement comes
    /// back as nothing, which would open the sheet at zero.
    @State private var isVisible: Bool = {
        if #available(iOS 18, *) { return true }
        return false
    }()
    @StateObject private var chromeController = LocktyDynamicSheetChromeController()
    /// How much of the screen the keyboard is covering.
    ///
    /// A sheet this size is a fixed detent, and a fixed detent does not get out of the
    /// keyboard's way -- so a field near the bottom of one ended up behind it, with the
    /// sheet lifting by a few points and no further. The detent has to grow by what the
    /// keyboard takes, which is what actually moves the sheet up.
    @State private var keyboardInset: CGFloat = 0


    var body: some View {
        if #available(iOS 26.0, *) {
            content
                .environment(\.locktyDynamicSheetChromeController, chromeController)
            // safeAreaInset, not a ZStack overlay: an overlay aligned to the top of a
            // stack is placed against that stack's bounds, which are not the sheet's --
            // so the bar drifted above the sheet's own edge. An inset is laid out by the
            // sheet, reserves its own room, and still lets scrolling content pass under.
                .safeAreaBar(edge: .top, spacing: 0) {
                    if let chrome = chromeController.configuration {
                        LocktyDynamicSheetChromeOverlay(configuration: chrome)
                            .transition(.blurReplace.combined(with: .opacity))
                        // The inset reserves exactly what the bar draws. Without a fixed
                        // height it reserved the buttons' 44 and the bar kept its own
                        // padding on top, so the two disagreed by the padding and the bar
                        // sat that much too high.
                            .frame(height: locktyDynamicSheetBarHeight)
                    }
                }
            /// As this will fix the size of the view in the vertical direction!
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGSize.self) {
                    isVisible ? $0.size : .zero
                } action: { newValue in
                    guard newValue != .zero else { return }
                    
                    if sheetHeight == .zero {
                        sheetHeight = min(newValue.height, windowSize.height)
                    } else {
                        withAnimation(animation) {
                            sheetHeight = min(newValue.height, windowSize.height)
                        }
                    }
                }
                .task { isVisible = true }
                .modifier(
                    LocktySheetDetentModifier(
                        height: presentedHeight,
                        resizableDetents: resizableDetents
                    )
                )
                .onReceive(keyboardHeightPublisher) { height in
                    withAnimation(.snappy(duration: 0.28)) { keyboardInset = height }
                }
        } else {
            content
                .environment(\.locktyDynamicSheetChromeController, chromeController)
            // safeAreaInset, not a ZStack overlay: an overlay aligned to the top of a
            // stack is placed against that stack's bounds, which are not the sheet's --
            // so the bar drifted above the sheet's own edge. An inset is laid out by the
            // sheet, reserves its own room, and still lets scrolling content pass under.
                .customSafeAreaBar(edge: .top, spacing: 0) {
                    if let chrome = chromeController.configuration {
                        LocktyDynamicSheetChromeOverlay(configuration: chrome)
                            .transition(.blurReplace.combined(with: .opacity))
                        // The inset reserves exactly what the bar draws. Without a fixed
                        // height it reserved the buttons' 44 and the bar kept its own
                        // padding on top, so the two disagreed by the padding and the bar
                        // sat that much too high.
                            .frame(height: locktyDynamicSheetBarHeight)
                    }
                }
            /// As this will fix the size of the view in the vertical direction!
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGSize.self) {
                    isVisible ? $0.size : .zero
                } action: { newValue in
                    guard newValue != .zero else { return }
                    
                    if sheetHeight == .zero {
                        sheetHeight = min(newValue.height, windowSize.height)
                    } else {
                        withAnimation(animation) {
                            sheetHeight = min(newValue.height, windowSize.height)
                        }
                    }
                }
                .task { isVisible = true }
                .modifier(
                    LocktySheetDetentModifier(
                        height: presentedHeight,
                        resizableDetents: resizableDetents
                    )
                )
                .onReceive(keyboardHeightPublisher) { height in
                    withAnimation(.snappy(duration: 0.28)) { keyboardInset = height }
                }
        }
    }

    /// Only when a screen named more than one size, which is the one case where being
    /// draggable means anything. Everything else is the measured height.
    private var resizableDetents: Set<PresentationDetent>? {
        guard let sizes = chromeController.sizes, sizes.count > 1 else { return nil }
        return Set(sizes.map(detent(for:)))
    }

    private func detent(for size: LocktyDynamicSheetSize) -> PresentationDetent {
        switch size {
        case .fit: sheetHeight == .zero ? .medium : .height(sheetHeight)
        case .small: .fraction(0.33)
        case .medium: .medium
        case .large: .large
        }
    }

    /// The measured height, plus room for the keyboard when one is up, never taller than
    /// the screen.
    private var presentedHeight: CGFloat {
        guard keyboardInset > 0 else { return sheetHeight }
        return min(sheetHeight + keyboardInset, windowSize.height)
    }

    /// The keyboard's height as it comes and goes. `willChangeFrame` rather than
    /// `willShow`, so a keyboard that swaps to a different height -- a suggestion bar
    /// appearing, a language with a taller layout -- moves the sheet too.
    private var keyboardHeightPublisher: AnyPublisher<CGFloat, Never> {
        let willChange = NotificationCenter.default
            .publisher(for: UIResponder.keyboardWillChangeFrameNotification)
            .map { notification -> CGFloat in
                let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
                return frame?.height ?? 0
            }

        let willHide = NotificationCenter.default
            .publisher(for: UIResponder.keyboardWillHideNotification)
            .map { _ in CGFloat(0) }

        return willChange.merge(with: willHide).eraseToAnyPublisher()
    }

    private var windowSize: CGSize {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.bounds.size ?? .zero
    }
}

/// Animatable so the height is interpolated frame by frame.
///
/// Swapping one detent for another hands the system two unrelated values with nothing in
/// between, so it can only cut. Interpolating the number and giving a new detent each
/// frame is what actually moves the sheet -- which is why every size, full height
/// included, arrives here as a number.
private struct LocktySheetDetentModifier: ViewModifier, Animatable {
    var height: CGFloat
    /// Set only when the screen named several sizes and can therefore be dragged.
    var resizableDetents: Set<PresentationDetent>?

    var animatableData: CGFloat {
        get { height }
        set { height = newValue }
    }

    private var detents: Set<PresentationDetent> {
        if let resizableDetents { return resizableDetents }
        // One detent, so there is nothing to drag to.
        return height == .zero ? [.medium] : [.height(height)]
    }

    func body(content: Content) -> some View {
        content.presentationDetents(detents)
    }
}

private struct LocktyDynamicSheetChromeOverlay: View {
    let configuration: LocktyDynamicSheetChromeController.Configuration
    @Namespace private var glassNamespace

    var body: some View {
        // 16 top and sides, the same gutter the content below it uses, so the buttons
        // line up with what they sit above. Only 4 underneath: the bar sits close to the
        // content it belongs to, not spaced off it.
        chromeContent
            .padding(.top, locktyDynamicSheetBarTopPadding)
            .padding(.horizontal, LocktySpacing.lg)
            .padding(.bottom, locktyDynamicSheetBarBottomPadding)
    }

    @ViewBuilder
    private var chromeContent: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: LocktySpacing.md) {
                baseChromeContent
                    .glassEffectTransition(.matchedGeometry)
            }
        } else {
            baseChromeContent
        }
    }

    /// Each slot is keyed to the screen, so a screen change replaces the button and the
    /// title rather than mutating them in place. Without the id they keep their identity
    /// across the change and a transition has nothing to run on -- the label just swaps.
    private var baseChromeContent: some View {
        HStack(spacing: LocktySpacing.md) {
            configuration.leading
                .frame(minWidth: locktyDynamicSheetBarButtonSize, minHeight: locktyDynamicSheetBarButtonSize, alignment: .leading)
                .modifier(LocktyGlassTransitionSlotModifier(id: "dynamic-sheet-leading", namespace: glassNamespace))
                .id(configuration.transitionID)
                .transition(.blurReplace.combined(with: .opacity))

            Spacer(minLength: 0)

            configuration.center
                .lineLimit(1)
                .id(configuration.transitionID)
                .transition(.blurReplace.combined(with: .opacity))

            Spacer(minLength: 0)

            configuration.trailing
                .frame(minWidth: locktyDynamicSheetBarButtonSize, minHeight: locktyDynamicSheetBarButtonSize, alignment: .trailing)
                .modifier(LocktyGlassTransitionSlotModifier(id: "dynamic-sheet-trailing", namespace: glassNamespace))
                .id(configuration.transitionID)
                .transition(.blurReplace.combined(with: .opacity))
        }
        .animation(.snappy(duration: 0.3, extraBounce: 0), value: configuration.transitionID)
    }
}

private struct LocktyGlassTransitionSlotModifier: ViewModifier {
    let id: String
    let namespace: Namespace.ID

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffectID(id, in: namespace)
        } else {
            content
        }
    }
}

struct LocktyDynamicSheetBarButton<Label: View>: View {
    let action: () -> Void
    let label: Label

    init(
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(action: action) {
            label
                .foregroundStyle(LocktyColors.primaryText)
                .frame(minWidth: 44, minHeight: 44)
                .safeGlass(radius: 22, interactive: true)
        }
        .buttonStyle(.locktyInteractive(brighten: true))
        .tappable()
    }
}
