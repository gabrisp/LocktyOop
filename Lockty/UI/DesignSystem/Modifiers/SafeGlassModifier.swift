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
            // The tint is honoured here too. It used to be dropped on this path, so a
            // control that reads as tinted glass on 26 came out as plain frosted grey on
            // 18 -- and anything drawn in `onPrimary`, which expects to sit on the tint,
            // became almost invisible.
            content
                .background {
                    shape.fill(.ultraThinMaterial)
                    if let tint {
                        shape.fill(tint.opacity(0.85))
                    }
                }
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
