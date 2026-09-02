import SwiftUI

/// Light added, or light taken away, depending on which there is more of.
///
/// Every glow in the app was written as `plusLighter`: a colour laid over the screen and
/// *added* to what is under it. On black that is the whole effect. On white there is
/// nothing left to add -- the ground is already at full brightness -- so auras, press
/// surfaces and the rock's bloom simply vanished in light mode, and the app looked like
/// half its rendering had failed.
///
/// The honest translation is not "make it stronger". It is that light and dark say the
/// same thing in opposite directions: on a dark ground colour arrives as light, and on a
/// light ground it arrives as shade. `multiply` is what darkens *with a colour* rather
/// than towards grey, so a green bloom stays green and the shape it lights still reads as
/// the same shape.
struct LocktyGlowModifier: ViewModifier {
    /// How strong it is in light mode relative to dark. Multiply is a stronger operator
    /// than plusLighter at the same opacity, so the values that were tuned against black
    /// come out heavy-handed against white unless they are pulled back.
    var lightScale: Double = 0.55

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if colorScheme == .dark {
            content.blendMode(.plusLighter)
        } else {
            content
                .opacity(lightScale)
                .blendMode(.multiply)
        }
    }
}

extension View {
    /// For anything that lights what is behind it: an aura, a bloom, a fill that grows.
    func locktyGlow(lightScale: Double = 0.55) -> some View {
        modifier(LocktyGlowModifier(lightScale: lightScale))
    }
}

/// The tint a press lays over a control, in whichever direction reads as pressed.
///
/// White on white is invisible; black on black is invisible. This is the same press
/// written for both grounds.
enum LocktyPressTint {
    static func color(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .white : .black
    }

    /// Adding on dark, laying over on light. A darkening press does not want a blend mode
    /// at all -- black at low opacity over a pale surface is exactly the effect.
    static func blendMode(for colorScheme: ColorScheme) -> BlendMode {
        colorScheme == .dark ? .plusLighter : .normal
    }

    static func secondaryBlendMode(for colorScheme: ColorScheme) -> BlendMode {
        colorScheme == .dark ? .screen : .normal
    }

    /// How far a pressed control moves in brightness. Up on dark, down on light: adding
    /// light to something already pale washes it out rather than bringing it forward.
    static func brightness(for colorScheme: ColorScheme, pressed: Bool, magnitude: Double) -> Double {
        guard pressed else { return 0 }
        return colorScheme == .dark ? magnitude : -magnitude * 0.35
    }
}
