import Combine
import SwiftUI
import UIKit

enum LocktyDynamicSheetNavigationDirection {
    case none
    case forward
    case backward
}

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

    let ownerID = UUID()
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

    let ownerID = UUID()
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

struct LocktyDynamicSheet<Content: View>: View {
    let animation: Animation
    /// Identity of the screen on show. Changing it crossfades the content and re-measures
    /// -- the sheet has no navigation stack, it swaps what is in it, so this is what
    /// stands in for a push.
    let contentID: AnyHashable?
    let navigationDirection: LocktyDynamicSheetNavigationDirection
    let content: Content

    @State private var sheetHeight: CGFloat = 0
    /// iOS 17 lays a sheet out before it is on screen and the first measurement comes
    /// back as nothing, which would open the sheet at zero.
    @State private var isVisible: Bool = {
        if #available(iOS 18, *) { return true }
        return false
    }()
    @StateObject private var chromeController = LocktyDynamicSheetChromeController()

    init(
        animation: Animation = .easeInOut(duration: 0.28),
        contentID: AnyHashable? = nil,
        navigationDirection: LocktyDynamicSheetNavigationDirection = .none,
        @ViewBuilder content: () -> Content
    ) {
        self.animation = animation
        self.contentID = contentID
        self.navigationDirection = navigationDirection
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .top) {
            transitionedContent
                .padding(.top, chromeController.configuration == nil ? 0 : 66)
                .id(contentID)
                .animation(animation, value: contentID)
                .environment(\.locktyDynamicSheetChromeController, chromeController)

            if let chrome = chromeController.configuration {
                LocktyDynamicSheetChromeOverlay(configuration: chrome)
                    .transition(.blurReplace.combined(with: .opacity))
            }
        }
        // Pins the content to its ideal height so it can be measured. There is no
        // navigation stack in the way to collapse -- the stack is faked by swapping
        // content -- which is what makes measuring directly possible at all.
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGSize.self) {
            isVisible ? $0.size : .zero
        } action: { newValue in
            guard newValue != .zero else { return }
            setHeight(newValue.height)
        }
        .task { isVisible = true }
        .modifier(LocktySheetDetentModifier(height: sheetHeight, sizes: chromeController.sizes))
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

    @ViewBuilder
    private var transitionedContent: some View {
        switch navigationDirection {
        case .none:
            content
                .transition(.blurReplace.combined(with: .opacity))
        case .forward:
            content
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .trailing)
                            .combined(with: AnyTransition(.blurReplace))
                            .combined(with: .opacity),
                        removal: .move(edge: .leading)
                            .combined(with: AnyTransition(.blurReplace))
                            .combined(with: .opacity)
                    )
                )
        case .backward:
            content
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .leading)
                            .combined(with: AnyTransition(.blurReplace))
                            .combined(with: .opacity),
                        removal: .move(edge: .trailing)
                            .combined(with: AnyTransition(.blurReplace))
                            .combined(with: .opacity)
                    )
                )
        }
    }
}

/// Animatable so the height is interpolated frame by frame.
///
/// Swapping one `.height` detent for another hands the system two unrelated values with
/// nothing in between, which is why resizing used to snap and needed a second detent kept
/// around to animate towards. Interpolating the number and giving a new detent each frame
/// is what actually moves it.
private struct LocktySheetDetentModifier: ViewModifier, Animatable {
    var height: CGFloat
    var sizes: [LocktyDynamicSheetSize]?

    var animatableData: CGFloat {
        get { height }
        set { height = newValue }
    }

    /// What the screen asked for, or the height it measured.
    ///
    /// One detent is a sheet that cannot be dragged anywhere, which is the point when the
    /// sheet is the size of its content. Several is the only case where dragging means
    /// something, and then it is resizable.
    private var detents: Set<PresentationDetent> {
        guard let sizes, !sizes.isEmpty else {
            return height == .zero ? [.medium] : [.height(height)]
        }
        return Set(sizes.map(detent(for:)))
    }

    private func detent(for size: LocktyDynamicSheetSize) -> PresentationDetent {
        switch size {
        case .fit: height == .zero ? .medium : .height(height)
        case .small: .fraction(0.33)
        case .medium: .medium
        case .large: .large
        }
    }

    func body(content: Content) -> some View {
        content.presentationDetents(detents)
    }
}

private struct LocktyDynamicSheetChromeOverlay: View {
    let configuration: LocktyDynamicSheetChromeController.Configuration
    @Namespace private var glassNamespace

    var body: some View {
        chromeContent
            .padding(.horizontal, LocktySpacing.md)
            .padding(.top, LocktySpacing.xs)
            .padding(.bottom, LocktySpacing.sm)
            // No background. A material paints its own tinted surface over whatever is
            // behind it, which made the bar read as a panel sitting on the content
            // rather than as part of the sheet.
            .background(alignment: .top) {
                Color.clear.blur(radius: 18)
            }
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

    private var baseChromeContent: some View {
        HStack(spacing: LocktySpacing.md) {
            configuration.leading
                .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                .modifier(LocktyGlassTransitionSlotModifier(id: "dynamic-sheet-leading", namespace: glassNamespace))

            Spacer(minLength: 0)

            configuration.center
                .lineLimit(1)

            Spacer(minLength: 0)

            configuration.trailing
                .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                .modifier(LocktyGlassTransitionSlotModifier(id: "dynamic-sheet-trailing", namespace: glassNamespace))
        }
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
        .buttonStyle(.plain)
        .tappable()
    }
}
