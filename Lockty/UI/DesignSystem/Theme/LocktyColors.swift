import SwiftUI

enum LocktyColors {
    static let secondaryDarkModeBg = Color(red: 0.025, green: 0.028, blue: 0.034)
    static let background = secondaryDarkModeBg
    static let elevatedBackground = Color.white.opacity(0.08)
    static let cardStroke = Color.white.opacity(0.12)
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.66)
    static let tertiaryText = Color.white.opacity(0.42)

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
