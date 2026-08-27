import SwiftUI

struct TappableModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.contentShape(Rectangle())
    }
}

extension View {
    func tappable() -> some View {
        modifier(TappableModifier())
    }
}
