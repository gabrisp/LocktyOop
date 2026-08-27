import Observation
import SwiftUI

enum LocktyAccent: String, CaseIterable, Identifiable, Codable, Hashable {
    case blue
    case white
    case pink

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blue: "Blue"
        case .white: "White"
        case .pink: "Pink"
        }
    }

    var color: Color {
        switch self {
        case .blue: Color(red: 0.36, green: 0.62, blue: 1.0)
        case .white: .white
        case .pink: Color(red: 1.0, green: 0.39, blue: 0.67)
        }
    }
}

@Observable
final class ThemeManager {
    var accent: LocktyAccent = .blue

    func selectAccent(_ accent: LocktyAccent) {
        self.accent = accent
    }
}
