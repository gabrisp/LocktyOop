import Foundation

protocol BaselineCalculating {
    func calculate(
        dailyUsages: [TimeInterval],
        baselineWindow: Int,
        currentWindow: Int
    ) -> UsageBaseline?
}

struct BaselineCalculator: BaselineCalculating {
    func calculate(
        dailyUsages: [TimeInterval],
        baselineWindow: Int = 7,
        currentWindow: Int = 7
    ) -> UsageBaseline? {
        let sanitizedUsages = dailyUsages.map { max($0, 0) }
        guard !sanitizedUsages.isEmpty else {
            return nil
        }

        let baselineSlice = Array(sanitizedUsages.prefix(max(baselineWindow, 1)))
        let currentSlice = Array(sanitizedUsages.suffix(max(currentWindow, 1)))

        let baselineAverage = average(baselineSlice)
        let currentAverage = average(currentSlice)

        return UsageBaseline(
            baselineAverageDailyUsage: baselineAverage,
            currentAverageDailyUsage: currentAverage,
            baselineWindowDayCount: baselineSlice.count,
            currentWindowDayCount: currentSlice.count,
            deltaPerDay: baselineAverage - currentAverage
        )
    }

    private func average(_ values: [TimeInterval]) -> TimeInterval {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}
