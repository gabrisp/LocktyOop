import Foundation

nonisolated enum MetricProvenance: String, Codable, Hashable {
    case measured
    case derived
    case estimated
    case projected
}
