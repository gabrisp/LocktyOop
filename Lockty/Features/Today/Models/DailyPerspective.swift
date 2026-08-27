import Foundation

enum DailyPerspectiveTone: String, Codable, Hashable {
    case excellent
    case focused
    case balanced
    case distracted
    case highDistraction
}

struct DailyPerspective: Codable, Hashable {
    let title: String
    let body: String
    let tone: DailyPerspectiveTone

    static let loading = DailyPerspective(
        title: "Preparing your day",
        body: "Lockty is rebuilding the digital story for this date.",
        tone: .balanced
    )
}
