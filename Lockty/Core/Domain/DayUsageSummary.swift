import Foundation

nonisolated struct DayKey: Codable, Hashable, Identifiable {
    let year: Int
    let month: Int
    let day: Int
    let calendarIdentifier: Calendar.Identifier
    let timeZoneIdentifier: String

    var id: String {
        "\(calendarIdentifier)-\(timeZoneIdentifier)-\(year)-\(month)-\(day)"
    }

    init(date: Date, calendar: Calendar = .current) {
        let timeZone = calendar.timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        year = components.year ?? 1970
        month = components.month ?? 1
        day = components.day ?? 1
        calendarIdentifier = calendar.identifier
        timeZoneIdentifier = timeZone.identifier
    }
}

nonisolated struct DayUsageSummary: Codable, Hashable {
    let day: DayKey
    var totalUsage: TimeInterval
    var applications: [ApplicationUsage]
}
