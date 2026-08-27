import Foundation

struct UsageTimelineOverlay: Codable, Hashable, Identifiable {
    let id: UUID
    let startDate: Date
    let endDate: Date
    let title: String
    let type: DigitalActivityType
}

struct UsageTimelineChartState: Codable, Hashable {
    let buckets: [UsageTimelineBucket]
    let overlays: [UsageTimelineOverlay]

    static let empty = UsageTimelineChartState(buckets: [], overlays: [])
}
