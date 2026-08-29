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
            .opacity(isPressed ? 0.86 : 1.0)
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
    var tint: Color = .white
    var pressedScale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        LocktyInteractiveButtonBody(
            configuration: configuration,
            shape: shape,
            tint: tint,
            pressedScale: pressedScale
        )
    }
}

private struct LocktyInteractiveButtonBody: View {
    let configuration: LocktyInteractiveButtonStyle.Configuration
    var shape: AnyShape?
    var tint: Color = .white
    var pressedScale: CGFloat = 0.97

    @State private var isShowingPressedState = false
    @State private var hapticTrigger = 0
    @State private var pressTaskID = UUID()

    var body: some View {
        configuration.label
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
