import SwiftUI

struct PressEffectModifier: ViewModifier {
    let isPressed: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .opacity(isPressed ? 0.86 : 1.0)
            .animation(.smooth(duration: 0.18), value: isPressed)
    }
}

extension View {
    func pressEffect(isPressed: Bool) -> some View {
        modifier(PressEffectModifier(isPressed: isPressed))
    }
}
