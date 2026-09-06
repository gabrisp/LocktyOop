import Foundation

/// Dates written the way they are said.
///
/// One place, because a date spelled two ways on two screens reads as two different
/// moments. Formatters are cached: building one is expensive, and these are called from
/// inside view bodies.
enum LocktyDateFormatting {
    /// "Tomorrow, 09:00" -- near enough to now that the day of the week is what people
    /// are actually asking, not the date.
    static func shortDayAndTime(_ date: Date) -> String {
        let calendar = Calendar.current

        let time = timeFormatter.string(from: date)

        if calendar.isDateInToday(date) { return "today, \(time)" }
        if calendar.isDateInTomorrow(date) { return "tomorrow, \(time)" }

        // Inside the week ahead the weekday is the clearest name a day has. Past that it
        // is a date, because "Tuesday" three weeks out means nothing.
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: date)).day ?? 0
        if days < 7 {
            return "\(weekdayFormatter.string(from: date)), \(time)"
        }

        return "\(dateFormatter.string(from: date)), \(time)"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEE")
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter
    }()
}
