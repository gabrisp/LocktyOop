import Foundation
import UserNotifications

/// The one notice that arrives because something has *not* happened.
///
/// Every other notification in Lockty is triggered by a real event -- minutes crossed, a
/// figure passed, a shield tapped. This one is the opposite: it goes off in the evening
/// when the day has not been earned yet, and is cancelled the moment it is.
///
/// Which is why it is scheduled rather than sent. There is no background moment at which
/// "nothing happened today" can be observed, so the notification is booked ahead each
/// time the streak is read and withdrawn as soon as the day counts.
nonisolated struct StreakReminderScheduler {
    /// When it arrives. Late enough that the day has had its chance, early enough that
    /// there is still an evening left to do something with.
    static let hour = 21
    private static let identifier = "streak-reminder"

    private let center = UNUserNotificationCenter.current()

    /// Books or withdraws the evening reminder.
    ///
    /// - Parameter isTodayEarned: whether the streak already counts today.
    /// - Parameter current: the run it would extend, which is what makes the line worth
    ///   reading. A reminder about a streak of nothing is a nag about nothing.
    func refresh(isTodayEarned: Bool, current: Int, now: Date = Date()) {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])

        guard !isTodayEarned, current > 0 else { return }

        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = Self.hour
        components.minute = 0

        // Not if the evening has already gone: a reminder booked for a time that has
        // passed is delivered by iOS at once, which is a notification about tonight
        // arriving at midnight.
        guard let fireDate = calendar.date(from: components), fireDate > now else { return }

        let content = UNMutableNotificationContent()
        content.title = "Do not let it go out"
        content.body = current == 1
            ? "One day so far. Run a routine, or come in under your usual, and it is two."
            : "\(current) days so far. Run a routine, or come in under your usual, and today counts."
        content.sound = .default

        center.add(
            UNNotificationRequest(
                identifier: Self.identifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(
                    dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate),
                    repeats: false
                )
            )
        )
    }
}
