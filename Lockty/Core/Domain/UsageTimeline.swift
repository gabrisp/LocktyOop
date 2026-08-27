import Foundation

enum TimelineConfidence: String, Codable, Hashable {
    case exact
    case inferred
    case limited
    case unavailable
}

struct UsageTimelineBucket: Codable, Hashable, Identifiable {
    let id: UUID
    var start: Date
    var end: Date
    var productive: TimeInterval
    var neutral: TimeInterval
    var unproductive: TimeInterval
    var confidence: TimelineConfidence

    init(
        id: UUID = UUID(),
        start: Date,
        end: Date,
        productive: TimeInterval,
        neutral: TimeInterval,
        unproductive: TimeInterval,
        confidence: TimelineConfidence = .inferred
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.productive = productive
        self.neutral = neutral
        self.unproductive = unproductive
        self.confidence = confidence
    }

    var aboveBaseline: TimeInterval {
        productive + neutral
    }
}

struct UsageActivityInterval: Codable, Hashable, Identifiable {
    let id: UUID
    var start: Date
    var end: Date

    init(id: UUID = UUID(), start: Date, end: Date) {
        self.id = id
        self.start = start
        self.end = end
    }
}
