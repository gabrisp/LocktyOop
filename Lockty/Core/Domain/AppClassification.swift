import Foundation

enum AppClassification: String, CaseIterable, Codable, Hashable, Identifiable {
    case productive
    case neutral
    case unproductive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .productive: "Productive"
        case .neutral: "Neutral"
        case .unproductive: "Unproductive"
        }
    }

    var scoringWeight: Double {
        switch self {
        case .productive: 1.0
        case .neutral: 0.5
        case .unproductive: 0.0
        }
    }
}
