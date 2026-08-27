import Foundation

struct DailyScoreResult: Codable, Hashable {
    var rawValue: Double
    var roundedValue: Int
    var progress: Double

    init(rawValue: Double) {
        let clampedValue = min(max(rawValue, 0), 100)

        self.rawValue = clampedValue
        self.roundedValue = Int(clampedValue.rounded())
        self.progress = clampedValue / 100
    }
}
