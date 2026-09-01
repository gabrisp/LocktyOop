import SwiftUI
import UIKit

private func adaptive(light: UIColor, dark: UIColor) -> Color {
    Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? dark : light
    })
}

enum LocktyColors {
    /// Global app background.
    ///
    /// Not white in light mode. Every surface in Lockty is a wash of the foreground over
    /// this, so on pure white the cards would have to be grey to be visible at all, and
    /// the screen would read as a stack of grey boxes on paper. A soft grey lets the
    /// cards be lighter than the page, the way they are darker than it in the dark.
    static let background = adaptive(
        light: UIColor(red: 0.945, green: 0.945, blue: 0.955, alpha: 1),
        dark: .black
    )

    /// A wash of the foreground over the background, whichever way round that is.
    ///
    /// Every card fill, hairline and scrim in the app was written as white at some
    /// opacity, which is only half a decision: it says "a little of the foreground" but
    /// spells it as a colour, so in light mode all of it disappeared. This says the
    /// intent instead.
    ///
    /// Light mode gets rather less of it. Black on a light ground reads far stronger than
    /// white on a dark one at the same alpha, so matching the numbers would make every
    /// hairline look drawn on with a pen.
    static func ink(_ opacity: Double) -> Color {
        adaptive(
            light: UIColor.black.withAlphaComponent(opacity * 0.62),
            dark: UIColor.white.withAlphaComponent(opacity)
        )
    }

    /// The soft blooms behind every screen. White either way: they are light spilling
    /// onto the page, and light on a grey page is white, not a darker grey.
    static let screenAura = adaptive(
        light: UIColor.white.withAlphaComponent(0.75),
        dark: UIColor.white.withAlphaComponent(0.03)
    )

    /// The colour to draw *on* a filled `primaryText` shape -- the label inside a
    /// selected pill, the glyph inside a stepper button.
    static let onPrimary = adaptive(light: .white, dark: .black)
    static let elevatedBackground = adaptive(
        light: UIColor.black.withAlphaComponent(0.06),
        dark: UIColor.white.withAlphaComponent(0.08)
    )
    static let cardFill = adaptive(
        light: UIColor.black.withAlphaComponent(0.05),
        dark: UIColor.white.withAlphaComponent(0.05)
    )
    static let cardStroke = adaptive(
        light: UIColor.black.withAlphaComponent(0.10),
        dark: UIColor.white.withAlphaComponent(0.12)
    )
    static let separator = Color(uiColor: .separator)

    /// Apple system default (backgrounds/secondary-elevated in the design file).
    static let fieldBackground = Color(uiColor: .secondarySystemBackground)
    static let primaryText = adaptive(light: .black, dark: .white)
    static let secondaryText = adaptive(
        light: UIColor.black.withAlphaComponent(0.60),
        dark: UIColor.white.withAlphaComponent(0.66)
    )
    static let tertiaryText = adaptive(
        light: UIColor.black.withAlphaComponent(0.38),
        dark: UIColor.white.withAlphaComponent(0.42)
    )

    static let productive = Color(red: 0.26, green: 0.86, blue: 0.50)
    static let neutral = Color(red: 0.66, green: 0.69, blue: 0.76)
    static let unproductive = Color(red: 1.0, green: 0.35, blue: 0.35)
    static let warning = Color(red: 1.0, green: 0.77, blue: 0.34)
    static let error = Color(red: 1.0, green: 0.31, blue: 0.31)

    static func classification(_ classification: AppClassification) -> Color {
        switch classification {
        case .productive: productive
        case .neutral: neutral
        case .unproductive: unproductive
        }
    }

    static func routine(_ color: RoutineColor) -> Color {
        switch color {
        case .mint:
            Color(red: 0.43, green: 0.92, blue: 0.76)
        case .sky:
            Color(red: 0.45, green: 0.78, blue: 1.0)
        case .amber:
            Color(red: 1.0, green: 0.78, blue: 0.40)
        case .coral:
            Color(red: 1.0, green: 0.54, blue: 0.49)
        case .rose:
            Color(red: 1.0, green: 0.48, blue: 0.71)
        case .violet:
            Color(red: 0.72, green: 0.58, blue: 1.0)
        }
    }
}
