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
