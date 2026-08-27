import DeviceActivity
import _DeviceActivity_SwiftUI
import Foundation
import ManagedSettings
import OSLog

private let reportLogger = Logger(subsystem: "com.gabrisp.Lockty", category: "screen-time-extension")

struct LocktyTotalActivityReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .locktyTotalActivity
    let content: (LocktyActivityReportConfiguration) -> LocktyTotalActivityView

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> LocktyActivityReportConfiguration {
        reportLogger.notice("makeConfiguration invoked")
        let snapshot = await buildSnapshot(from: data)

        if let snapshot {
            reportLogger.notice("Built snapshot day=\(snapshot.day.id, privacy: .public) totalActivityDuration=\(snapshot.totalActivityDuration, privacy: .public) apps=\(snapshot.applications.count, privacy: .public) segments=\(snapshot.activitySegments.count, privacy: .public)")
            do {
                try AppGroupStore().saveScreenTimeReportSnapshot(snapshot)
                reportLogger.notice("Saved snapshot to App Group for day=\(snapshot.day.id, privacy: .public)")
            } catch {
                reportLogger.error("Failed to save snapshot: \(error.localizedDescription, privacy: .public)")
            }
        } else {
            reportLogger.notice("buildSnapshot returned nil (no activity segments in the received data)")
        }

        return LocktyActivityReportConfiguration(totalActivityDuration: snapshot?.totalActivityDuration ?? 0)
    }

    private func buildSnapshot(
        from data: DeviceActivityResults<DeviceActivityData>
    ) async -> ScreenTimeReportSnapshot? {
        var totalActivityDuration: TimeInterval = 0
        var totalPickupsWithoutApplicationActivity = 0
        var longestActivityDuration: TimeInterval?
        var firstPickup: Date?
        var lastUpdatedAt = Date.distantPast
        var applications: [AppIdentity.ID: ScreenTimeApplicationSnapshot] = [:]
        var webDomains: [String: ScreenTimeWebDomainSnapshot] = [:]
        var activitySegments: [ScreenTimeActivitySegmentSnapshot] = []
        var firstSegmentDate: Date?

        for await activityData in data {
            lastUpdatedAt = max(lastUpdatedAt, activityData.lastUpdatedDate)

            for await segment in activityData.activitySegments {
                totalActivityDuration += segment.totalActivityDuration
                totalPickupsWithoutApplicationActivity += segment.totalPickupsWithoutApplicationActivity
                if let longestActivity = segment.longestActivity {
                    let duration = longestActivity.duration
                    longestActivityDuration = max(longestActivityDuration ?? 0, duration)
                }
                if let pickup = segment.firstPickup {
                    firstPickup = min(firstPickup ?? pickup, pickup)
                }

                firstSegmentDate = min(firstSegmentDate ?? segment.dateInterval.start, segment.dateInterval.start)
                var applicationDurations: [AppIdentity.ID: TimeInterval] = [:]

                for await category in segment.categories {
                    for await applicationActivity in category.applications {
                        let appIdentity: AppIdentity
                        if let token = applicationActivity.application.token {
                            appIdentity = AppIdentity(token: token)
                        } else {
                            let bundleIdentifier = applicationActivity.application.bundleIdentifier
                            let displayName = applicationActivity.application.localizedDisplayName ?? bundleIdentifier ?? "App"
                            appIdentity = AppIdentity(
                                id: AppIdentity.ID(rawValue: bundleIdentifier ?? "display.\(displayName.lowercased())"),
                                displayName: displayName,
                                bundleIdentifier: bundleIdentifier,
                                iconSystemName: "app.fill",
                                iconSource: .screenTimeToken
                            )
                        }
                        applicationDurations[appIdentity.id, default: 0] += applicationActivity.totalActivityDuration
                        var aggregate = applications[appIdentity.id, default: ScreenTimeApplicationSnapshot(
                            app: appIdentity,
                            totalActivityDuration: 0,
                            pickups: 0,
                            notifications: 0
                        )]
                        aggregate.totalActivityDuration += applicationActivity.totalActivityDuration
                        aggregate.pickups += applicationActivity.numberOfPickups
                        aggregate.notifications += applicationActivity.numberOfNotifications
                        applications[appIdentity.id] = aggregate
                    }

                    for await domainActivity in category.webDomains {
                        guard let domain = domainActivity.webDomain.domain else { continue }
                        webDomains[domain, default: ScreenTimeWebDomainSnapshot(domain: domain, totalActivityDuration: 0)].totalActivityDuration += domainActivity.totalActivityDuration
                    }
                }

                activitySegments.append(
                    ScreenTimeActivitySegmentSnapshot(
                        id: segment.dateInterval.start.ISO8601Format(),
                        dateInterval: segment.dateInterval,
                        totalActivityDuration: segment.totalActivityDuration,
                        totalPickupsWithoutApplicationActivity: segment.totalPickupsWithoutApplicationActivity,
                        longestActivity: segment.longestActivity,
                        firstPickup: segment.firstPickup,
                        applicationDurations: applicationDurations
                    )
                )
            }
        }

        guard let firstSegmentDate else { return nil }

        return ScreenTimeReportSnapshot(
            day: DayKey(date: firstSegmentDate),
            totalActivityDuration: totalActivityDuration,
            totalPickupsWithoutApplicationActivity: totalPickupsWithoutApplicationActivity,
            longestActivityDuration: longestActivityDuration,
            firstPickup: firstPickup,
            lastUpdatedAt: lastUpdatedAt == .distantPast ? Date() : lastUpdatedAt,
            applications: applications.values.sorted { $0.totalActivityDuration > $1.totalActivityDuration },
            activitySegments: activitySegments.sorted { $0.dateInterval.start < $1.dateInterval.start },
            webDomains: webDomains.values.sorted { $0.totalActivityDuration > $1.totalActivityDuration }
        )
    }
}

struct LocktyActivityReportConfiguration: Hashable {
    var totalActivityDuration: TimeInterval
}
