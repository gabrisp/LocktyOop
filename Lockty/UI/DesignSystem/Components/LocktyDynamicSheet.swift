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
    /// matched, so the sheet stayed on the size the screen it left had asked for and
    /// never went back to measuring the content.
    @State private var ownerID = UUID()
    let sizes: [LocktyDynamicSheetSize]

    func body(content: Content) -> some View {
        content
            .onAppear {
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
    /// The height the sheet had before a screen took it to a size of its own.
    @State private var heightBeforeExplicitSize: CGFloat?

    var body: some View {
        ZStack(alignment: .top) {
            content
                .padding(.top, chromeController.configuration == nil ? 0 : 66)
                .environment(\.locktyDynamicSheetChromeController, chromeController)
                // On the content, inside the stack: applied outside it these take in the
                // bar overlay too, and the bar sits on top of the content rather than
                // under it, so what came back was neither the content's height nor a
                // stable one.
                // Only while the sheet is sizing itself to the content. A screen that
                // named its own size wants to fill the sheet it asked for, and pinning
                // it to its ideal height leaves it sitting at the top of an empty one.
                .fixedSize(horizontal: false, vertical: chromeController.sizes == nil)
                .frame(maxHeight: chromeController.sizes == nil ? nil : .infinity)
                .onGeometryChange(for: CGSize.self) {
                    isVisible ? $0.size : .zero
                } action: { newValue in
                    guard newValue != .zero, chromeController.sizes == nil else { return }
                    // Not while coming back from a screen that took its own size: the
                    // height to return to was already measured on the way in, and
                    // reading again mid-transition catches the content still moving.
                    guard heightBeforeExplicitSize == nil else { return }
                    setHeight(newValue.height)
                }

            if let chrome = chromeController.configuration {
                LocktyDynamicSheetChromeOverlay(configuration: chrome)
                    .transition(.blurReplace.combined(with: .opacity))
            }
        }
        .task { isVisible = true }
        .onChange(of: chromeController.sizes == nil) { _, isMeasuring in
            if isMeasuring {
                // Back to sizing itself: restore what it was, rather than measuring the
                // returning screen again.
                if let heightBeforeExplicitSize {
                    withAnimation(animation) { sheetHeight = heightBeforeExplicitSize }
                }
                // Released a beat later so the transition finishes before measurements
                // are taken up again.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(360))
                    heightBeforeExplicitSize = nil
                }
            } else {
                heightBeforeExplicitSize = sheetHeight
            }
        }
        // Animated on the target height rather than on the sizes changing: what the
        // modifier interpolates is the number, so the number is what has to move.
        .animation(animation, value: targetHeight)
        .modifier(
            LocktySheetDetentModifier(
                height: targetHeight,
                resizableDetents: resizableDetents
            )
        )
    }

    /// The one height the sheet should be right now, as a number.
    ///
    /// Even .large is a number here. Going from .height(x) to .large is a change of
    /// detent kind, and there is nothing between the two for the animation to run
    /// through -- it can only cut. Height to height is a value that can be interpolated,
    /// and the system clamps the tall one to what the screen can actually show.
    private var targetHeight: CGFloat {
        guard let sizes = chromeController.sizes, sizes.count == 1, let only = sizes.first else {
            return sheetHeight
        }
        return height(for: only)
    }

    private func height(for size: LocktyDynamicSheetSize) -> CGFloat {
        switch size {
        case .fit: sheetHeight
        case .small: windowSize.height * 0.33
        case .medium: windowSize.height * 0.5
        case .large: windowSize.height
        }
    }

    /// Only when a screen named more than one size, which is the only case where being
    /// draggable means anything.
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

    private func setHeight(_ height: CGFloat) {
        let resolved = min(height, windowSize.height - 110)
        guard resolved > 0 else { return }

        if sheetHeight == .zero {
            sheetHeight = resolved
        } else {
            withAnimation(animation) { sheetHeight = resolved }
        }
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
            .padding(.top, LocktySpacing.lg)
            .padding(.horizontal, LocktySpacing.lg)
            .padding(.bottom, LocktySpacing.xs)
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
                .frame(minWidth: 44, minHeight: 44, alignment: .leading)
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
                .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
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
            // Bare glyph, no glass behind it: the bar is not a surface, so a button that
            // brings its own reads as a chip stuck onto it.
            label
                .foregroundStyle(LocktyColors.primaryText)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.locktyInteractive(brighten: true))
        .tappable()
    }
}
