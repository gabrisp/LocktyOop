import SwiftUI

extension View {
    /// A light travelling around the edge of a shape.
    ///
    /// Used on the buttons that commit something, while they are being held. A static
    /// border says "this is a button"; a border with something running around it says the
    /// button is *doing* something right now, which is exactly the state a hold is.
    ///
    /// Adapted from Balaji Venkatesh's BorderBeamEffect.
    func locktyBorderBeam(
        border: Color = .white,
        beam: [Color],
        beamBlur: CGFloat = 15,
        cornerRadius: CGFloat,
        isEnabled: Bool = true
    ) -> some View {
        modifier(
            LocktyBorderBeamModifier(
                border: border,
                beam: beam,
                beamBlur: beamBlur,
                cornerRadius: cornerRadius,
                isEnabled: isEnabled
            )
        )
    }
}

private struct LocktyBorderBeamModifier: ViewModifier {
    let border: Color
    let beam: [Color]
    let beamBlur: CGFloat
    let cornerRadius: CGFloat
    let isEnabled: Bool

    func body(content: Content) -> some View {
        content
            .overlay {
                if isEnabled {
                    beamView
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(.smooth(duration: 0.25), value: isEnabled)
    }

    /// The beam is one angular gradient rotated on a loop, used twice: once as the
    /// stroke, and once as the mask over a colour gradient so only the arc under the
    /// travelling light is tinted.
    private var beamView: some View {
        KeyframeAnimator(initialValue: 0.0, repeating: true) { value in
            let rotation = value * 360

            let borderGradient = AngularGradient(
                colors: [.clear, border, .clear],
                center: .center,
                startAngle: .degrees(140 + rotation),
                endAngle: .degrees(270 + rotation)
            )

            let beamGradient = LinearGradient(
                colors: beam,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(beamGradient)
                    // Inverse mask: a blurred copy of the shape punched out of a solid
                    // rectangle leaves only a soft band at the edge. Blur rather than
                    // padding, so the band fades out instead of ending on a hard line.
                    .mask {
                        Rectangle()
                            .overlay {
                                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                    .blur(radius: beamBlur)
                                    .blendMode(.destinationOut)
                            }
                    }
                    // Then masked again by the travelling arc, so the colour only shows
                    // where the light currently is rather than all the way round.
                    .mask {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(borderGradient)
                            .blur(radius: beamBlur / 1.5)
                            .padding(-beamBlur * 2)
                    }

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(borderGradient, lineWidth: 0.8)
            }
        } keyframes: { _ in
            LinearKeyframe(1, duration: 2.5)
        }
    }
}
