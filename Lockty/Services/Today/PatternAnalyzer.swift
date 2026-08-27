import Foundation

struct PatternInput: Codable, Hashable {
    var productivityScore: Int
    var controlScore: Int
    var longestDetoxText: String
    var completedRoutines: Int
    var totalRoutines: Int
}

protocol PatternAnalyzing {
    func patterns(from input: PatternInput) -> [BehaviorPattern]
}

struct PatternAnalyzer: PatternAnalyzing {
    func patterns(from input: PatternInput) -> [BehaviorPattern] {
        [
            BehaviorPattern(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000501")!,
                title: "Deep Work protects focus",
                body: "Days with completed focus routines trend higher on Productivity and reduce late distraction windows.",
                tone: input.completedRoutines == input.totalRoutines ? .positive : .neutral
            ),
            BehaviorPattern(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000502")!,
                title: "Detox window",
                body: "Your longest phone-free block usually appears between 11:00 and 14:00. Today it reached \(input.longestDetoxText).",
                tone: .positive
            ),
            BehaviorPattern(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000503")!,
                title: "Control gap",
                body: "Control is lower than Productivity when restriction attempts cluster after focused work.",
                tone: input.controlScore < input.productivityScore ? .warning : .neutral
            )
        ]
    }
}
