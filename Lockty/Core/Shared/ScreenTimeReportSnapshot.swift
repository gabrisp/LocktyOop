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
}

nonisolated struct ScreenTimeWebDomainSnapshot: Codable, Hashable, Identifiable {
    var id: String { domain }
    var domain: String
    var totalActivityDuration: TimeInterval
}
