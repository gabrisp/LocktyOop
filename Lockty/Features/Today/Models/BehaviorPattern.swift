import Foundation

enum BehaviorPatternTone: String, Codable, Hashable {
    case positive
    case neutral
    case warning
}

struct BehaviorPattern: Codable, Hashable, Identifiable {
    let id: UUID
    let title: String
    let body: String
    let tone: BehaviorPatternTone
}
