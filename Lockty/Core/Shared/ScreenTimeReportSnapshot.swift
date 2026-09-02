import Foundation

nonisolated struct ScreenTimeReportSnapshotEnvelope: Codable, Hashable {
    var schemaVersion: Int
    var writtenAt: Date
    var snapshot: ScreenTimeReportSnapshot

    static let currentSchemaVersion = 1

    nonisolated static func current(_ snapshot: ScreenTimeReportSnapshot) -> ScreenTimeReportSnapshotEnvelope {
        ScreenTimeReportSnapshotEnvelope(
            schemaVersion: currentSchemaVersion,
            writtenAt: Date(),
            snapshot: snapshot
        )
    }
}

nonisolated struct ScreenTimeReportSnapshot: Codable, Hashable {
    var day: DayKey
    var totalActivityDuration: TimeInterval
    var totalPickupsWithoutApplicationActivity: Int
    var longestActivityDuration: TimeInterval?
    var firstPickup: Date?
    var lastUpdatedAt: Date
    var applications: [ScreenTimeApplicationSnapshot]
    var activitySegments: [ScreenTimeActivitySegmentSnapshot]
    var webDomains: [ScreenTimeWebDomainSnapshot]
}

nonisolated struct ScreenTimeApplicationSnapshot: Codable, Hashable, Identifiable {
    var app: AppIdentity
    var totalActivityDuration: TimeInterval
    var pickups: Int
    var notifications: Int

    var id: AppIdentity.ID { app.id }
}

nonisolated struct ScreenTimeActivitySegmentSnapshot: Codable, Hashable, Identifiable {
    let id: String
    var dateInterval: DateInterval
    var totalActivityDuration: TimeInterval
    var totalPickupsWithoutApplicationActivity: Int
    var longestActivity: DateInterval?
    var firstPickup: Date?
    var applicationDurations: [AppIdentity.ID: TimeInterval]
    /// Pickups and notifications inside this hour, summed across every app in it.
    ///
    /// The snapshot already carried both per app for the whole day, which answers "how
    /// many" and not "when" -- and when is the only question a chart of hours is asking.
    var pickups: Int
    var notifications: Int

    init(
        id: String,
        dateInterval: DateInterval,
        totalActivityDuration: TimeInterval,
        totalPickupsWithoutApplicationActivity: Int,
        longestActivity: DateInterval? = nil,
        firstPickup: Date? = nil,
        applicationDurations: [AppIdentity.ID: TimeInterval],
        pickups: Int = 0,
        notifications: Int = 0
    ) {
        self.id = id
        self.dateInterval = dateInterval
        self.totalActivityDuration = totalActivityDuration
        self.totalPickupsWithoutApplicationActivity = totalPickupsWithoutApplicationActivity
        self.longestActivity = longestActivity
        self.firstPickup = firstPickup
        self.applicationDurations = applicationDurations
        self.pickups = pickups
        self.notifications = notifications
    }

    // Snapshots are cached in the app group and read back by the extensions, so one
    // written before these two existed has to decode as zero rather than throw and take
    // the day's whole history with it.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        dateInterval = try container.decode(DateInterval.self, forKey: .dateInterval)
        totalActivityDuration = try container.decode(TimeInterval.self, forKey: .totalActivityDuration)
        totalPickupsWithoutApplicationActivity = try container.decode(Int.self, forKey: .totalPickupsWithoutApplicationActivity)
        longestActivity = try container.decodeIfPresent(DateInterval.self, forKey: .longestActivity)
        firstPickup = try container.decodeIfPresent(Date.self, forKey: .firstPickup)
        applicationDurations = try container.decode([AppIdentity.ID: TimeInterval].self, forKey: .applicationDurations)
        pickups = try container.decodeIfPresent(Int.self, forKey: .pickups) ?? 0
        notifications = try container.decodeIfPresent(Int.self, forKey: .notifications) ?? 0
    }
}

nonisolated struct ScreenTimeWebDomainSnapshot: Codable, Hashable, Identifiable {
    var id: String { domain }
    var domain: String
    var totalActivityDuration: TimeInterval
}
