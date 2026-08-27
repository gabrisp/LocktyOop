import Foundation

enum DigitalActivityType: String, CaseIterable, Codable, Hashable, Identifiable {
    case routine
    case focus
    case detox
    case breakPeriod
    case freeTime
    case distraction

    var id: String { rawValue }

    var title: String {
        switch self {
        case .routine: "Routine"
        case .focus: "Focus"
        case .detox: "Detox"
        case .breakPeriod: "Break"
        case .freeTime: "Free Time"
        case .distraction: "Distraction"
        }
    }
}

struct DigitalActivity: Codable, Hashable, Identifiable {
    let id: UUID
    let type: DigitalActivityType
    let startDate: Date
    let endDate: Date
    let title: String
    let productivityScore: Double?
    let relatedApplications: [AppIdentity]
    let routineID: UUID?

    var duration: TimeInterval {
        max(endDate.timeIntervalSince(startDate), 0)
    }
}
