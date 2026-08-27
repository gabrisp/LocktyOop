import Foundation
import DeviceActivity
import ManagedSettings
import OSLog
import _DeviceActivity_SwiftUI

private func usageLogger() -> Logger {
    Logger(subsystem: "com.gabrisp.Lockty", category: "screen-time")
}

struct LiveUsageDataService: UsageDataServicing {
    private let appGroupStore: AppGroupStore
    private let classificationRepository: AppClassificationRepository

    init(
        appGroupStore: AppGroupStore = AppGroupStore(),
        classificationRepository: AppClassificationRepository
    ) {
        self.appGroupStore = appGroupStore
        self.classificationRepository = classificationRepository
    }

    func usageSummary(for day: Date) async throws -> DayUsageSummary {
        usageLogger().notice("Requesting usage summary for \(DayKey(date: day).id, privacy: .public)")
        let snapshot = try await snapshot(for: day)
        let key = DayKey(date: day)

        let applications = await snapshot.applications.asyncMap { applicationSnapshot in
            let classification = await classificationRepository.classification(for: applicationSnapshot.app.id) ?? .neutral
            return ApplicationUsage(
                app: applicationSnapshot.app,
                duration: applicationSnapshot.totalActivityDuration,
                classification: classification
            )
        }

        return DayUsageSummary(
            day: key,
            totalUsage: snapshot.totalActivityDuration,
            applications: applications.sorted { $0.duration > $1.duration }
        )
    }

    func mostUsedApplications(for day: Date) async throws -> [ApplicationUsage] {
        try await usageSummary(for: day).applications
    }

    private func snapshot(for day: Date) async throws -> ScreenTimeReportSnapshot {
        let dayKey = DayKey(date: Calendar.current.startOfDay(for: day))
        if let cachedSnapshot = try appGroupStore.loadScreenTimeReportSnapshot(for: dayKey) {
            usageLogger().notice("Using cached DeviceActivityReport snapshot for \(dayKey.id, privacy: .public)")
            return cachedSnapshot
        }

        usageLogger().error("No DeviceActivityReport snapshot available for \(dayKey.id, privacy: .public)")
        throw UsageDataError.unavailable
    }
}

private extension Sequence {
    func asyncMap<T>(_ transform: (Element) async -> T) async -> [T] {
        var values: [T] = []
        values.reserveCapacity(underestimatedCount)
        for element in self {
            values.append(await transform(element))
        }
        return values
    }
}
