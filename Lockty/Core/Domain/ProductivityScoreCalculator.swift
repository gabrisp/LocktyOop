import Foundation

struct ProductivityScoreResult: Codable, Hashable {
    var rawValue: Double?
    var roundedValue: Int?
    var totalUsage: TimeInterval

    static let noData = ProductivityScoreResult(
        rawValue: nil,
        roundedValue: nil,
        totalUsage: 0
    )
}

protocol ProductivityScoring {
    func score(for usage: [ClassifiedUsageDuration]) -> ProductivityScoreResult
}

struct WeightedProductivityScoreCalculator: ProductivityScoring {
    func score(for usage: [ClassifiedUsageDuration]) -> ProductivityScoreResult {
        let totalUsage = usage.reduce(0) { $0 + max($1.duration, 0) }
        guard totalUsage > 0 else {
            return .noData
        }

        let weightedUsage = usage.reduce(0) { partialResult, item in
            partialResult + max(item.duration, 0) * item.classification.scoringWeight
        }
        let rawScore = (weightedUsage / totalUsage) * 100

        return ProductivityScoreResult(
            rawValue: rawScore,
            roundedValue: Int(rawScore.rounded()),
            totalUsage: totalUsage
        )
    }
}

/// What finishing things adds to the Focus score.
///
/// Focus is a share of the time -- how the day divided between apps you called
/// productive and apps you did not. That is a reading of *what the screen was*, and it
/// says nothing about the day you actually meant to have: a morning of unproductive
/// minutes with the checklist done and the water drunk is not the same day as the same
/// minutes with neither.
///
/// So the two things you set out to do are worth up to ten points between them. Not more:
/// they are a correction to a measurement of screen time, not a second score wearing its
/// name. And nothing at all when there was nothing to finish -- an empty checklist must
/// not be worth five points for being empty.
nonisolated struct FocusCreditCalculator {
    /// The most the two can add, in points.
    static let maximum: Double = 10

    nonisolated func credit(
        completedTasks: Int,
        totalTasks: Int,
        completedObjectives: Int,
        totalObjectives: Int
    ) -> Double {
        let halves = [
            share(completedTasks, of: totalTasks),
            share(completedObjectives, of: totalObjectives)
        ].compactMap { $0 }

        guard !halves.isEmpty else { return 0 }

        // Split between whichever of the two the day actually had. With only a checklist,
        // finishing it is worth the whole ten -- there was nothing else to do.
        let average = halves.reduce(0, +) / Double(halves.count)
        return average * Self.maximum
    }

    private func share(_ completed: Int, of total: Int) -> Double? {
        guard total > 0 else { return nil }
        return min(Double(completed) / Double(total), 1)
    }
}
