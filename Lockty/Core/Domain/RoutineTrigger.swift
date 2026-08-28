import Foundation

nonisolated enum RoutineTrigger: Codable, Hashable, Identifiable {
    case manual
    case schedule(RoutineSchedule)
    case alarm(RoutineAlarmTrigger)
    case nfc(NFCAction)
    case location(LocationTrigger)

    var id: String {
        switch self {
        case .manual:
            "manual"
        case .schedule(let schedule):
            "schedule-\(schedule.id.uuidString)"
        case .alarm(let alarm):
            "alarm-\(alarm.id.uuidString)"
        case .nfc(let action):
            "nfc-\(action.id.uuidString)"
        case .location(let trigger):
            "location-\(trigger.id.uuidString)"
        }
    }
}

nonisolated struct RoutineSchedule: Codable, Hashable, Identifiable {
    let id: UUID
    var hour: Int
    var minute: Int
    var endHour: Int
    var endMinute: Int
    var weekdays: Set<Weekday>
    var timeZoneIdentifier: String

    init(
        id: UUID = UUID(),
        hour: Int,
        minute: Int,
        endHour: Int = 17,
        endMinute: Int = 0,
        weekdays: Set<Weekday>,
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) {
        self.id = id
        self.hour = hour
        self.minute = minute
        self.endHour = endHour
        self.endMinute = endMinute
        self.weekdays = weekdays
        self.timeZoneIdentifier = timeZoneIdentifier
    }
}

nonisolated enum Weekday: Int, Codable, CaseIterable, Hashable, Identifiable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7

    var id: Int { rawValue }
}

nonisolated struct RoutineAlarmTrigger: Codable, Hashable, Identifiable {
    let id: UUID
    var hour: Int
    var minute: Int
    var alarmIdentifier: String?

    init(id: UUID = UUID(), hour: Int, minute: Int, alarmIdentifier: String? = nil) {
        self.id = id
        self.hour = hour
        self.minute = minute
        self.alarmIdentifier = alarmIdentifier
    }
}

nonisolated struct NFCAction: Codable, Hashable, Identifiable {
    nonisolated enum Kind: String, Codable, Hashable {
        case startRoutine
        case startBreak
        case endBreak
    }

    let id: UUID
    var tagIdentifier: String
    var kind: Kind
    var routineID: UUID?

    init(
        id: UUID = UUID(),
        tagIdentifier: String,
        kind: Kind,
        routineID: UUID? = nil
    ) {
        self.id = id
        self.tagIdentifier = tagIdentifier
        self.kind = kind
        self.routineID = routineID
    }
}

nonisolated struct LocationTrigger: Codable, Hashable, Identifiable {
    let id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var radiusMeters: Double
    var startsOnEntry: Bool

    init(
        id: UUID = UUID(),
        name: String,
        latitude: Double,
        longitude: Double,
        radiusMeters: Double,
        startsOnEntry: Bool = true
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.radiusMeters = radiusMeters
        self.startsOnEntry = startsOnEntry
    }
}
