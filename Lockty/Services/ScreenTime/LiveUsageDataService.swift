import Foundation
import DeviceActivity
import FamilyControls
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
        try await usageSummary(for: day, preferCached: false)
    }

    func usageSummary(for day: Date, preferCached: Bool) async throws -> DayUsageSummary {
        usageLogger().notice("Requesting usage summary for \(DayKey(date: day).id, privacy: .public)")
        print("Requesting usage summary for \(DayKey(date: day).id)")
        let snapshot = try await snapshot(for: day, preferCached: preferCached)
        let key = DayKey(date: day)

        // Names filled in from the catalogue the report extension keeps. A snapshot
        // written before the extension started recording them -- or one whose app was
        // only ever seen as a token -- carries a stand-in name; the catalogue is where
        // the real one lives.
        let catalog = appGroupStore.loadAppNameCatalog()

        let applications = await snapshot.applications.asyncMap { applicationSnapshot in
            let classification = await classificationRepository.classification(for: applicationSnapshot.app.id) ?? .neutral
            return ApplicationUsage(
                app: applicationSnapshot.app.resolved(with: catalog),
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

    private func snapshot(for day: Date, preferCached: Bool = false) async throws -> ScreenTimeReportSnapshot {
        let dayKey = DayKey(date: Calendar.current.startOfDay(for: day))
        print("Resolving snapshot for \(dayKey.id)")

        // What was written the last time this day was read, handed back immediately. The
        // live query below is the truth and still runs -- this is only so the screen has
        // the day's real figures on it while that happens, instead of zeroes.
        if preferCached, let cachedSnapshot = try? appGroupStore.loadScreenTimeReportSnapshot(for: dayKey) {
            usageLogger().notice("Using cached Screen Time snapshot for \(dayKey.id, privacy: .public) by preference")
            print("Using cached Screen Time snapshot for \(dayKey.id) by preference")
            return cachedSnapshot
        }

        if supportsDirectActivityData {
            do {
                if let directSnapshot = try await directSnapshot(for: dayKey) {
                    // The names, filed as well as the figures.
                    //
                    // The catalogue used to be written only by the report extension, and
                    // this path -- the live query, which is what actually runs on 26.4 and
                    // up -- resolved the same names and threw them away. Anything reading
                    // the catalogue afterwards (a notification naming the app you have been
                    // in, a snapshot that only ever saw a token) found nothing there.
                    appGroupStore.noteAppNames(from: directSnapshot)
                    try? appGroupStore.saveScreenTimeReportSnapshot(directSnapshot)
                    usageLogger().notice("Using direct DeviceActivityData access for \(dayKey.id, privacy: .public)")
                    print("Using direct DeviceActivityData access for \(dayKey.id)")
                    return directSnapshot
                }
                print("Direct DeviceActivityData returned no snapshot for \(dayKey.id)")
            } catch {
                usageLogger().error("Direct DeviceActivityData failed for \(dayKey.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                print("Direct DeviceActivityData failed for \(dayKey.id): \(error.localizedDescription)")
            }
        }

        if let cachedSnapshot = try appGroupStore.loadScreenTimeReportSnapshot(for: dayKey) {
            usageLogger().notice("Using cached Screen Time snapshot for \(dayKey.id, privacy: .public)")
            print("Using cached Screen Time snapshot for \(dayKey.id)")
            return cachedSnapshot
        }

        if supportsDirectActivityData {
            usageLogger().error("Direct DeviceActivityData access returned no snapshot for \(dayKey.id, privacy: .public)")
            print("Direct DeviceActivityData access returned no snapshot for \(dayKey.id)")
            throw UsageDataError.noData
        }

        usageLogger().error("Screen Time data access unavailable for \(dayKey.id, privacy: .public)")
        print("Screen Time data access unavailable for \(dayKey.id)")
        throw UsageDataError.dataAccessUnavailable
    }

    private var supportsDirectActivityData: Bool {
        if #available(iOS 26.4, *) {
            print("AuthorizationCenter status=\(AuthorizationCenter.shared.authorizationStatus.description)")
            return true
        }
        print("Direct DeviceActivityData access unavailable before iOS 26.4")
        return false
    }

    private func directSnapshot(for dayKey: DayKey) async throws -> ScreenTimeReportSnapshot? {
        guard #available(iOS 26.4, *) else {
            return nil
        }

        let calendar = Calendar.current
        guard
            let start = calendar.date(from: DateComponents(year: dayKey.year, month: dayKey.month, day: dayKey.day)),
            let rawEnd = calendar.date(byAdding: .day, value: 1, to: start)
        else {
            return nil
        }
        let end = min(rawEnd, Date())
        let installedApplications = await installedApplicationsByBundleIdentifier()

        let filter = DeviceActivityFilter(
            segment: .hourly(during: DateInterval(start: start, end: end)),
            devices: nil,
            applications: [],
            categories: [],
            webDomains: []
        )

        // The cache first, the system itself when the cache has nothing.
        //
        // `.cached` only holds what Lockty has already been shown, so every day before it
        // was installed -- and any day it happened not to be opened -- came back empty.
        // That is why the history started at the install rather than at the phone. `.live`
        // asks Screen Time, which has been keeping these figures all along.
        //
        // The fallback rather than the default because it is the slower of the two, and
        // today is re-read constantly: a day already in the cache never pays for it.
        for policy in [DeviceActivityData.Policy.cached, .live] {
            let results = DeviceActivityData.activityData(filteredBy: filter, using: policy)
            print("Started direct DeviceActivityData request for \(dayKey.id) using \(policy)")

            if let snapshot = try await buildSnapshot(
                from: results,
                dayStart: start,
                installedApplications: installedApplications
            ) {
                return snapshot
            }
        }

        return nil
    }

    private func buildSnapshot<S: AsyncSequence>(
        from results: S,
        dayStart: Date,
        installedApplications: [String: Application]
    ) async throws -> ScreenTimeReportSnapshot? where S.Element == DeviceActivityData {
        var totalActivityDuration: TimeInterval = 0
        var totalPickupsWithoutApplicationActivity = 0
        var longestActivityDuration: TimeInterval?
        var firstPickup: Date?
        var lastUpdatedAt = Date.distantPast
        var applications: [AppIdentity.ID: ScreenTimeApplicationSnapshot] = [:]
        var webDomains: [String: ScreenTimeWebDomainSnapshot] = [:]
        var activitySegments: [ScreenTimeActivitySegmentSnapshot] = []

        for try await activityData in results {
            print("Received DeviceActivityData chunk updatedAt=\(activityData.lastUpdatedDate)")
            lastUpdatedAt = max(lastUpdatedAt, activityData.lastUpdatedDate)

            for await segment in activityData.activitySegments {
                print("Processing activity segment \(segment.dateInterval.start) -> \(segment.dateInterval.end) total=\(segment.totalActivityDuration)")
                totalActivityDuration += segment.totalActivityDuration
                totalPickupsWithoutApplicationActivity += segment.totalPickupsWithoutApplicationActivity

                if let longestActivity = segment.longestActivity {
                    let duration = longestActivity.duration
                    longestActivityDuration = max(longestActivityDuration ?? 0, duration)
                }

                if let pickup = segment.firstPickup {
                    firstPickup = min(firstPickup ?? pickup, pickup)
                }

                var applicationDurations: [AppIdentity.ID: TimeInterval] = [:]
                var segmentPickups = 0
                var segmentNotifications = 0

                for await category in segment.categories {
                    for await applicationActivity in category.applications {
                        let appIdentity = makeAppIdentity(
                            from: applicationActivity.application,
                            installedApplications: installedApplications
                        )
                        print("App activity \(appIdentity.displayName) duration=\(applicationActivity.totalActivityDuration) pickups=\(applicationActivity.numberOfPickups) notifications=\(applicationActivity.numberOfNotifications)")
                        applicationDurations[appIdentity.id, default: 0] += applicationActivity.totalActivityDuration
                        segmentPickups += applicationActivity.numberOfPickups
                        segmentNotifications += applicationActivity.numberOfNotifications

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
                        applicationDurations: applicationDurations,
                        pickups: segmentPickups + segment.totalPickupsWithoutApplicationActivity,
                        notifications: segmentNotifications
                    )
                )
            }
        }

        guard !activitySegments.isEmpty || totalActivityDuration > 0 || !applications.isEmpty else {
            print("No activity segments or applications found in direct DeviceActivityData result")
            return nil
        }

        print("Built direct snapshot for \(DayKey(date: dayStart).id) apps=\(applications.count) segments=\(activitySegments.count) total=\(totalActivityDuration)")

        return ScreenTimeReportSnapshot(
            day: DayKey(date: dayStart),
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

    private func makeAppIdentity(
        from application: Application,
        installedApplications: [String: Application]
    ) -> AppIdentity {
        if let bundleIdentifier = application.bundleIdentifier,
           let installed = installedApplications[bundleIdentifier],
           let token = installed.token {
            return AppIdentity(
                id: AppIdentity.ID(rawValue: bundleIdentifier),
                displayName: AppIdentity.preferredDisplayName(
                    localizedDisplayName: installed.localizedDisplayName ?? application.localizedDisplayName,
                    bundleIdentifier: bundleIdentifier
                ),
                bundleIdentifier: bundleIdentifier,
                applicationToken: token,
                iconSystemName: nil,
                iconSource: .screenTimeToken
            )
        }

        if let token = application.token {
            return AppIdentity(token: token)
        }

        let bundleIdentifier = application.bundleIdentifier
        let displayName = AppIdentity.preferredDisplayName(
            localizedDisplayName: application.localizedDisplayName,
            bundleIdentifier: bundleIdentifier
        )
        return AppIdentity(
            id: AppIdentity.ID(rawValue: bundleIdentifier ?? "display.\(displayName.lowercased())"),
            displayName: displayName,
            bundleIdentifier: bundleIdentifier,
            iconSystemName: bundleIdentifier == nil ? "app.fill" : nil,
            iconSource: bundleIdentifier == nil ? .placeholder : .screenTimeToken
        )
    }

    private func installedApplicationsByBundleIdentifier() async -> [String: Application] {
        guard #available(iOS 26.4, *) else {
            return [:]
        }

        do {
            let applications = try await FamilyActivityData.shared.installedApplications
            print("Loaded installed applications count=\(applications.count)")
            return applications.reduce(into: [:]) { partialResult, application in
                guard let bundleIdentifier = application.bundleIdentifier else { return }
                partialResult[bundleIdentifier] = application
            }
        } catch {
            print("Failed loading installed applications: \(error.localizedDescription)")
            return [:]
        }
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
