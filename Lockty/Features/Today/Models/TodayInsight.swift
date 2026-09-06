import Foundation

/// One thing worth saying about the day, in a sentence.
///
/// Written the way a good notification is written: the figure first, then what it means,
/// and nothing at all when there is nothing to say. Every one of these is guarded on a
/// threshold -- "you used your phone today" is not an insight, and a card that appears
/// every single day stops being read within a week.
struct TodayInsight: Identifiable, Equatable {
    enum Tone: Equatable {
        case good
        case neutral
        case warning
    }

    let id: String
    let systemImage: String
    let title: String
    let message: String
    let tone: Tone
}

/// Reads the day and picks the few things worth putting on the screen.
///
/// In the model layer rather than the view because it is a set of judgements about
/// numbers, not a layout: what counts as "a lot" of anything is the interesting part, and
/// it should be somewhere it can be read and argued with.
enum TodayInsightBuilder {
    /// At most this many are built. The stack shows three at a time and brings the next
    /// one forward as each is thrown away, so this is how deep the pile can go rather
    /// than how much is on screen.
    private static let maximum = 6

    /// How much of a day has to have happened before any of this is worth saying.
    ///
    /// A reading taken at nine in the morning is a reading of one hour, and "most of
    /// today was distracting apps" over twelve minutes of use is technically true and
    /// completely useless. Both bars have to clear: an hour on the clock and half an
    /// hour actually spent on the phone.
    private static let minimumElapsed: TimeInterval = 60 * 60
    private static let minimumUsage: TimeInterval = 30 * 60

    static func insights(for state: TodayDayState, now: Date = Date()) -> [TodayInsight] {
        guard case .loaded = state.loadingState else { return [] }

        let hourly = state.hourlyActivity

        // Only today is young. A day being read back has already happened, whatever the
        // clock says right now.
        let calendar = Calendar.current
        if calendar.isDate(state.day, inSameDayAs: now) {
            let elapsed = now.timeIntervalSince(calendar.startOfDay(for: now))
            guard elapsed >= minimumElapsed, hourly.totalUsage >= minimumUsage else { return [] }
        }

        var found: [TodayInsight] = []

        // The app that took the day, when one of them really did. A leading app is only
        // worth naming if it is a decent share of the time -- otherwise this is just the
        // top row of the list below, said twice.
        if let top = state.appUsages.max(by: { $0.duration < $1.duration }),
           top.duration >= 20 * 60,
           hourly.totalUsage > 0 {
            let share = top.duration / hourly.totalUsage
            if share >= 0.25 {
                let spent = LocktyDurationFormatter.abbreviated(top.duration)
                let tone: TodayInsight.Tone = top.classification == .unproductive ? .warning : .neutral
                found.append(
                    TodayInsight(
                        id: "top-app",
                        systemImage: "hourglass",
                        title: "\(spent) on \(top.app.displayName)",
                        message: "That is \(percentText(share)) of everything you spent on the phone today.",
                        tone: tone
                    )
                )
            }
        }

        // How the day is going against the one before it. A quarter of an hour either way
        // is the floor: below that the difference is noise, and calling noise progress is
        // how a number stops meaning anything.
        if let delta = state.metrics.screenTime.deltaVersusPreviousDay, abs(delta) >= 15 * 60 {
            let amount = LocktyDurationFormatter.abbreviated(abs(delta))
            let isLighter = delta > 0
            found.append(
                TodayInsight(
                    id: "versus-yesterday",
                    systemImage: isLighter ? "arrow.down.right" : "arrow.up.right",
                    title: isLighter ? "\(amount) less than yesterday" : "\(amount) more than yesterday",
                    message: isLighter
                        ? "Today is lighter than the day before it."
                        : "Today is heavier than the day before it.",
                    tone: isLighter ? .good : .warning
                )
            )
        }

        // Pickups against an ordinary day of your own. Not against a number somebody
        // decided was healthy: there isn't one.
        if let baseline = hourly.baselineUnlocks, baseline > 0, hourly.totalUnlocks > 0 {
            let ratio = Double(hourly.totalUnlocks) / baseline
            if ratio >= 1.25 {
                found.append(
                    TodayInsight(
                        id: "pickups-high",
                        systemImage: "iphone.gen3",
                        title: "\(hourly.totalUnlocks) pickups",
                        message: "About \(percentText(ratio - 1)) more than you usually reach for it.",
                        tone: .warning
                    )
                )
            } else if ratio <= 0.75 {
                found.append(
                    TodayInsight(
                        id: "pickups-low",
                        systemImage: "iphone.gen3",
                        title: "\(hourly.totalUnlocks) pickups",
                        message: "About \(percentText(1 - ratio)) fewer than you usually reach for it.",
                        tone: .good
                    )
                )
            }
        }

        // A stretch long enough to have done something else in.
        if let stretch = state.metrics.bestDetox.duration, stretch >= 90 * 60 {
            let away = LocktyDurationFormatter.abbreviated(stretch)
            found.append(
                TodayInsight(
                    id: "longest-stretch",
                    systemImage: "moon.zzz",
                    title: "\(away) away from it",
                    message: "Your longest unbroken stretch off the phone today.",
                    tone: .good
                )
            )
        }

        // Where the time actually went, when most of it went one way.
        let unproductive = state.appUsages
            .filter { $0.classification == .unproductive }
            .reduce(0) { $0 + $1.duration }
        if hourly.totalUsage > 30 * 60, unproductive / hourly.totalUsage >= 0.5 {
            let spent = LocktyDurationFormatter.abbreviated(unproductive)
            let total = LocktyDurationFormatter.abbreviated(hourly.totalUsage)
            found.append(
                TodayInsight(
                    id: "unproductive-share",
                    systemImage: "exclamationmark.bubble",
                    title: "Most of today was distracting apps",
                    message: "\(spent) of \(total) went to apps you have called unproductive.",
                    tone: .warning
                )
            )
        }

        // A quiet day for interruptions is worth as much as a loud one, and nobody ever
        // gets told about it.
        if let baseline = hourly.baselineNotifications, baseline > 0, hourly.totalNotifications > 0 {
            let ratio = Double(hourly.totalNotifications) / baseline
            if ratio <= 0.7 {
                found.append(
                    TodayInsight(
                        id: "notifications-low",
                        systemImage: "bell.slash",
                        title: "\(hourly.totalNotifications) notifications",
                        message: "A quieter day than usual -- about \(percentText(1 - ratio)) fewer.",
                        tone: .good
                    )
                )
            }
        }

        return Array(found.prefix(maximum))
    }

    /// A share as a round percentage. Rounded to five, because the underlying figures are
    /// minutes reported by Screen Time and "37%" claims a precision they do not have.
    private static func percentText(_ share: Double) -> String {
        let rounded = (share * 100 / 5).rounded() * 5
        return "\(Int(max(rounded, 5)))%"
    }
}
