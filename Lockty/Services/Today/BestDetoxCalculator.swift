import Foundation

struct BestDetoxResult: Equatable {
    var duration: TimeInterval?
    var confidence: TimelineConfidence

    static let unavailable = BestDetoxResult(duration: nil, confidence: .unavailable)
}

struct BestDetoxCalculator {
    func longestInactivePeriod(
        usageIntervals: [UsageActivityInterval],
        dayStart: Date,
        dayEnd: Date
    ) -> BestDetoxResult {
        guard dayEnd > dayStart else { return .unavailable }
        let intervals = usageIntervals
            .map { interval in
                UsageActivityInterval(
                    start: max(interval.start, dayStart),
                    end: min(interval.end, dayEnd)
                )
            }
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }

        guard !intervals.isEmpty else {
            return BestDetoxResult(duration: dayEnd.timeIntervalSince(dayStart), confidence: .inferred)
        }

        var cursor = dayStart
        var longest: TimeInterval = 0

        for interval in intervals {
            longest = max(longest, interval.start.timeIntervalSince(cursor))
            cursor = max(cursor, interval.end)
        }

        longest = max(longest, dayEnd.timeIntervalSince(cursor))
        return BestDetoxResult(duration: longest, confidence: .inferred)
    }
}
