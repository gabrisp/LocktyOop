import SwiftUI

struct SafeGlassModifier: ViewModifier {
    let radius: CGFloat
    let interactive: Bool
    let tint: Color?

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        if #available(iOS 26.0, *) {
            if interactive {
                if let tint {
                    content.glassEffect(
                        .regular.tint(tint).interactive(),
                        in: shape
                    )
                } else {
                    content.glassEffect(
                        .regular.interactive(),
                        in: shape
                    )
                }
            } else {
                if let tint {
                    content.glassEffect(
                        .regular.tint(tint),
                        in: shape
                    )
                } else {
                    content.glassEffect(
                        .regular,
                        in: shape
                    )
                }
            }
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay {
                    shape.stroke(LocktyColors.cardStroke, lineWidth: 1)
                }
        }
    }
}

extension View {
    func safeGlass(
        radius: CGFloat = LocktyRadius.large,
        interactive: Bool = false,
        tint: Color? = nil
    ) -> some View {
        modifier(
            SafeGlassModifier(
                radius: radius,
                interactive: interactive,
                tint: tint
            )
        )
    }
}
