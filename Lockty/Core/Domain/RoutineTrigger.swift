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

    /// The run covering `date`, or nil when the schedule is not due then.
    ///
    /// Read in the schedule's own time zone: a routine written for nine in Madrid is a
    /// nine-o'clock routine wherever the phone happens to be.
    ///
    /// An end at or before the start is the next morning -- 22:00 to 06:00 is one window
    /// across midnight, not an empty one -- so yesterday is tried too, and the weekday
    /// checked is the day the window *opened*. Friday night belongs to Friday.
    nonisolated func window(containing date: Date) -> DateInterval? {
        guard !weekdays.isEmpty else { return nil }

        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current

        for dayOffset in [0, -1] {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: date),
                  let weekday = Weekday(rawValue: calendar.component(.weekday, from: day)),
                  weekdays.contains(weekday)
            else { continue }

            var components = calendar.dateComponents([.year, .month, .day], from: day)
            components.hour = hour
            components.minute = minute
            components.second = 0
            guard let start = calendar.date(from: components) else { continue }

            components.hour = endHour
            components.minute = endMinute
            guard var end = calendar.date(from: components) else { continue }
            if end <= start {
                guard let overnight = calendar.date(byAdding: .day, value: 1, to: end) else { continue }
                end = overnight
            }

            if date >= start, date < end { return DateInterval(start: start, end: end) }
        }
        return nil
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

    /// Monday first, the way a week is written here. `allCases` follows the raw values,
    /// which start on Sunday because that is what Calendar's weekday numbering does.
    static let orderedWeek: [Weekday] = [
        .monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday
    ]

    /// The initial on a weekday circle.
    ///
    /// English, like the rest of the app. Two of them repeat -- Tuesday and Thursday
    /// both start with T, Saturday and Sunday with S -- which is why they are read in
    /// order rather than individually, and why the row is always the whole week.
    var shortLabel: String {
        switch self {
        case .monday: "M"
        case .tuesday: "T"
        case .wednesday: "W"
        case .thursday: "T"
        case .friday: "F"
        case .saturday: "S"
        case .sunday: "S"
        }
    }
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
