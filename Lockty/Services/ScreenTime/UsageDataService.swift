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
    /// The same summary, but taking whatever is already written down over asking Screen
    /// Time for a fresh reading.
    ///
    /// The live query takes seconds, and everything on Today waits on it: coming back to
    /// the app showed a screen of zeroes until it landed, as though nothing had been kept.
    /// It had been -- the day is written to the App Group every time it is read -- so this
    /// is the reading that paints the screen while the real one is on its way.
    func usageSummary(for day: Date, preferCached: Bool) async throws -> DayUsageSummary
    func mostUsedApplications(for day: Date) async throws -> [ApplicationUsage]
}

extension UsageDataServicing {
    /// For anything that has no cache of its own to prefer.
    func usageSummary(for day: Date, preferCached: Bool) async throws -> DayUsageSummary {
        try await usageSummary(for: day)
    }
}
