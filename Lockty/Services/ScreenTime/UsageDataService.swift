import Foundation

enum UsageDataError: LocalizedError {
    case unavailable
    case noData
    case dataAccessUnavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Screen Time usage data is unavailable for the requested date."
        case .noData:
            "No Screen Time usage data is available for the requested date yet."
        case .dataAccessUnavailable:
            "Screen Time data access is unavailable for this build or authorization state."
        }
    }
}

protocol UsageDataServicing {
    func usageSummary(for day: Date) async throws -> DayUsageSummary
    func mostUsedApplications(for day: Date) async throws -> [ApplicationUsage]
}
