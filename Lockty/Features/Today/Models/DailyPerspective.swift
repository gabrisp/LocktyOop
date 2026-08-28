import Foundation

enum DailyPerspectiveTone: String, Codable, Hashable {
    case excellent
    case focused
    case balanced
    case distracted
    case highDistraction
}

struct DailyPerspective: Codable, Hashable {
    let id: String
    let title: String
    let body: String
    let tone: DailyPerspectiveTone

    init(
        id: String = UUID().uuidString,
        title: String,
        body: String,
        tone: DailyPerspectiveTone
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.tone = tone
    }

    static let loading = DailyPerspective(
        id: "loading",
        title: "Preparing your day",
        body: "Lockty is rebuilding the digital story for this date.",
        tone: .balanced
    )

    static let loadingStack: [DailyPerspective] = [
        DailyPerspective(
            id: "loading-1",
            title: "Rebuilding the day",
            body: "Lockty is collecting the timeline and application usage for this date.",
            tone: .balanced
        ),
        DailyPerspective(
            id: "loading-2",
            title: "Calculating metrics",
            body: "Productivity, Control and Detox are being recalculated from the available data.",
            tone: .focused
        ),
        DailyPerspective(
            id: "loading-3",
            title: "Preparing insights",
            body: "Meaningful patterns for this day will appear here as soon as the pipeline finishes.",
            tone: .excellent
        )
    ]
}
