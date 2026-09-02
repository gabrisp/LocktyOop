import SwiftUI

private struct LocktySurfacePressedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var locktySurfacePressed: Bool {
        get { self[LocktySurfacePressedKey.self] }
        set { self[LocktySurfacePressedKey.self] = newValue }
    }
}

struct PressEffectModifier: ViewModifier {
    let isPressed: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.98 : 1.0)
            // Lit, not dimmed. Fading a control on press says it is becoming
            // unavailable, which is the opposite of what a press means -- and on a dark
            // screen a dimmed thing simply recedes. Adding light brings it forward.
            .brightness(isPressed ? 0.14 : 0)
            .animation(.smooth(duration: 0.18), value: isPressed)
    }
}

private struct LocktyInteractiveSurfaceModifier<S: Shape>: ViewModifier {
    let enabled: Bool
    let tint: Color
    let shape: S
    let pressedScale: CGFloat

    @Environment(\.locktySurfacePressed) private var isPressed

    func body(content: Content) -> some View {
        content
            .overlay {
                if enabled {
                    shape
                        .fill(tint.opacity(isPressed ? 0.09 : 0))
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                        .animation(.smooth(duration: 0.18), value: isPressed)
                }
            }
            .overlay {
                if enabled {
                    shape
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: tint.opacity(isPressed ? 0.13 : 0), location: 0),
                                    .init(color: tint.opacity(isPressed ? 0.05 : 0), location: 0.35),
                                    .init(color: .clear, location: 0.72),
                                    .init(color: .clear, location: 1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .blendMode(.screen)
                        .allowsHitTesting(false)
                        .animation(.smooth(duration: 0.18), value: isPressed)
                }
            }
            .compositingGroup()
            .scaleEffect(enabled && isPressed ? pressedScale : 1)
            .animation(.smooth(duration: 0.18), value: isPressed)
    }
}

struct LocktyInteractiveButtonStyle: ButtonStyle {
    /// When set, the style draws the press surface itself.
    ///
    /// Applying `locktyInteractiveSurface` next to `buttonStyle` looks right and does
    /// nothing: the style publishes the pressed state into the *label's* environment, so
    /// a surface chained onto the Button from outside never sees it and the button just
    /// sits there. Handing the shape to the style puts the surface where it can read it.
    var shape: AnyShape?
    /// Lights the label itself instead of laying a shape over it.
    ///
    /// For content that already has its own silhouette -- an app icon, say -- where any
    /// shape drawn on top is a rectangle sitting over the artwork. Adding light to what
    /// is there needs no shape at all.
    var brightens = false
    var tint: Color = .white
    var pressedScale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        LocktyInteractiveButtonBody(
            configuration: configuration,
            shape: shape,
            brightens: brightens,
            tint: tint,
            pressedScale: pressedScale
        )
    }
}

private struct LocktyInteractiveButtonBody: View {
    let configuration: LocktyInteractiveButtonStyle.Configuration
    var shape: AnyShape?
    var brightens = false
    var tint: Color = .white
    var pressedScale: CGFloat = 0.97

    @State private var isShowingPressedState = false
    @State private var hapticTrigger = 0
    @State private var pressTaskID = UUID()

    var body: some View {
        configuration.label
            .brightness(brightens && isShowingPressedState ? 0.16 : 0)
            .saturation(brightens && isShowingPressedState ? 1.1 : 1)
            .scaleEffect(brightens && isShowingPressedState ? pressedScale : 1)
            .locktyInteractiveSurface(
                enabled: shape != nil,
                tint: tint,
                shape: shape ?? AnyShape(Rectangle()),
                pressedScale: pressedScale
            )
            .environment(\.locktySurfacePressed, isShowingPressedState)
            .animation(.smooth(duration: 0.18), value: isShowingPressedState)
            .sensoryFeedback(.impact(weight: .light), trigger: hapticTrigger)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    hapticTrigger += 1
                    let taskID = UUID()
                    pressTaskID = taskID
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(120))
                        guard pressTaskID == taskID, configuration.isPressed else { return }
                        withAnimation(.smooth(duration: 0.16)) {
                            isShowingPressedState = true
                        }
                    }
                } else {
                    pressTaskID = UUID()
                    withAnimation(.smooth(duration: 0.18)) {
                        isShowingPressedState = false
                    }
                }
            }
    }
}

extension ButtonStyle where Self == LocktyInteractiveButtonStyle {
    /// For a label that draws its own press surface, such as CardView.
    static var locktyInteractive: LocktyInteractiveButtonStyle {
        LocktyInteractiveButtonStyle()
    }

    /// For everything else: the style shrinks and highlights the button itself.
    static func locktyInteractive<S: Shape>(
        shape: S,
        tint: Color = .white,
        pressedScale: CGFloat = 0.97
    ) -> LocktyInteractiveButtonStyle {
        LocktyInteractiveButtonStyle(shape: AnyShape(shape), tint: tint, pressedScale: pressedScale)
    }

    /// For a row in a list: lights its contents and taps back, with no shape drawn over
    /// it. A row has no silhouette of its own to fill, and a rectangle laid across one is
    /// a highlight bar rather than the row responding.
    static var locktyRow: LocktyInteractiveButtonStyle {
        LocktyInteractiveButtonStyle(brightens: true, pressedScale: 0.99)
    }

    /// For artwork: brightens what is there rather than putting a shape over it.
    static func locktyInteractive(
        brighten: Bool,
        pressedScale: CGFloat = 0.97
    ) -> LocktyInteractiveButtonStyle {
        LocktyInteractiveButtonStyle(brightens: brighten, pressedScale: pressedScale)
    }
}

extension View {
    func pressEffect(isPressed: Bool) -> some View {
        modifier(PressEffectModifier(isPressed: isPressed))
    }

    func locktyInteractiveSurface<S: Shape>(
        enabled: Bool = true,
        tint: Color = .white,
        shape: S,
        // Pressing shrinks. Growing under the finger reads as the control escaping the
        // touch rather than accepting it, and on a rounded surface it also pushes the
        // corner radius out past the shape the highlight is drawn in.
        pressedScale: CGFloat = 0.97
    ) -> some View {
        modifier(
            LocktyInteractiveSurfaceModifier(
                enabled: enabled,
                tint: tint,
                shape: shape,
                pressedScale: pressedScale
            )
        )
    }
}

/// A long press that answers while it is held, and then acts.
///
/// Two ways of answering, because two things get held. A row inside a card has no
/// silhouette of its own, so it *brightens* -- a rectangle laid across it reads as a
/// highlight bar rather than as the row responding. A menu item does have one, and gets
/// the same surface a button gets, drawn in its own rounded rectangle: it is a control in
/// a panel of controls, and the shape is what says which one is under your finger.
private struct LocktyLongPressModifier: ViewModifier {
    /// Nil brightens; a shape draws the surface in it.
    let shape: AnyShape?
    let minimumDuration: Double
    let action: () -> Void

    @State private var isPressed = false
    @State private var hapticTrigger = 0

    func body(content: Content) -> some View {
        content
            .brightness(shape == nil && isPressed ? 0.16 : 0)
            .saturation(shape == nil && isPressed ? 1.1 : 1)
            .scaleEffect(isPressed ? 0.99 : 1)
            .animation(.smooth(duration: 0.18), value: isPressed)
            .locktyInteractiveSurface(
                enabled: shape != nil,
                shape: shape ?? AnyShape(Rectangle())
            )
            .environment(\.locktySurfacePressed, isPressed)
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: minimumDuration) {
                hapticTrigger += 1
                action()
            } onPressingChanged: { pressing in
                isPressed = pressing
            }
            // Impact on the way in and success when it fires, so the hold has an end you
            // can feel rather than one you have to watch for.
            .sensoryFeedback(.impact(weight: .light), trigger: isPressed) { _, new in new }
            .sensoryFeedback(.success, trigger: hapticTrigger)
    }
}

extension View {
    /// Held, and lit by brightening. For a row inside a card.
    func locktyLongPress(
        minimumDuration: Double = 0.35,
        action: @escaping () -> Void
    ) -> some View {
        modifier(
            LocktyLongPressModifier(
                shape: nil,
                minimumDuration: minimumDuration,
                action: action
            )
        )
    }

    /// Held, and lit by drawing the surface in the given shape. For a menu item.
    func locktyLongPress<S: Shape>(
        shape: S,
        minimumDuration: Double = 0.35,
        action: @escaping () -> Void
    ) -> some View {
        modifier(
            LocktyLongPressModifier(
                shape: AnyShape(shape),
                minimumDuration: minimumDuration,
                action: action
            )
        )
    }
}

extension View {
    /// Holding one line of a summary opens the editor for what it summarises.
    ///
    /// Per row, not per card. The gesture is meant to point at a thing -- hold the
    /// schedule, get the schedule -- and a card-wide press lights the entire summary,
    /// which says only "this whole panel is a button", which it is not.
    ///
    /// A no-op when there is nothing to open, so a preview shown somewhere that cannot
    /// edit -- a routine that is running, a friction being read from a rule -- neither
    /// lights up nor pretends it will do something.
    @ViewBuilder
    func locktyEditOnLongPress(_ action: (() -> Void)?) -> some View {
        if let action {
            locktyLongPress(action: action)
        } else {
            self
        }
    }
}
