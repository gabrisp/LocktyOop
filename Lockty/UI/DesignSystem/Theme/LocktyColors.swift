import SwiftUI
import UIKit

private func adaptive(light: UIColor, dark: UIColor) -> Color {
    Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? dark : light
    })
}

enum LocktyColors {
    /// Global app background. Lockty currently runs in dark appearance only.
    static let background = Color.black
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
}
