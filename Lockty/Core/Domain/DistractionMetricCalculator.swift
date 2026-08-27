import Foundation

struct DistractionMetricInput: Codable, Hashable {
    var restrictedAccessAttempts: Int
    var unproductiveBursts: Int
    var repeatedAttempts: Int
}

protocol DistractionMetricCalculating {
    func count(from input: DistractionMetricInput) -> Int
}

struct DistractionMetricCalculator: DistractionMetricCalculating {
    func count(from input: DistractionMetricInput) -> Int {
        max(input.restrictedAccessAttempts, 0)
            + max(input.unproductiveBursts, 0)
            + max(input.repeatedAttempts, 0)
    }
}
