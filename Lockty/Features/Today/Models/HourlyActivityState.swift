import Foundation

/// A day in twenty-four columns, measured three ways.
///
/// The three are on the same axis on purpose: time spent, times picked up, and times
/// interrupted are the same day told from three sides, and switching between them is a
/// far more useful thing to be able to do than reading three charts stacked down a
/// screen. The reduction figure at the head is the fourth question -- is any of this
/// getting better -- and is the only one that needs yesterday to answer.
struct HourlyActivityState: Equatable {
    struct Hour: Equatable, Identifiable {
        /// 0 through 23. Also the id: there is exactly one of each in a day.
        var hour: Int
        var usage: TimeInterval
        var unlocks: Int
        var notifications: Int
        /// The hour's usage split by what the apps in it are called.
        ///
        /// Carried per hour rather than derived later because the split only exists in
        /// the segment: once an hour is a single duration, the question of what that hour
        /// was spent on has already been thrown away.
        var productive: TimeInterval
        var neutral: TimeInterval
        var unproductive: TimeInterval

        var id: Int { hour }

        init(
            hour: Int,
            usage: TimeInterval,
            unlocks: Int,
            notifications: Int,
            productive: TimeInterval = 0,
            neutral: TimeInterval = 0,
            unproductive: TimeInterval = 0
        ) {
            self.hour = hour
            self.usage = usage
            self.unlocks = unlocks
            self.notifications = notifications
            self.productive = productive
            self.neutral = neutral
            self.unproductive = unproductive
        }

        /// What the three add up to, which is not always the hour's own total: Screen
        /// Time reports a segment total that can exceed the apps inside it. The bar is
        /// drawn against this so its pieces always fill it exactly.
        var classifiedTotal: TimeInterval {
            productive + neutral + unproductive
        }
    }

    var hours: [Hour]
    /// How much less was used today than on an average day before, or nil when there is
    /// not enough history to say. Negative means more, not less.
    ///
    /// Optional rather than zero: "no change" and "we do not know yet" are different
    /// answers, and showing the first when the second is true is the kind of number
    /// people quietly build a belief on.
    var reductionVersusBaseline: TimeInterval?

    static let empty = HourlyActivityState(
        hours: (0..<24).map { Hour(hour: $0, usage: 0, unlocks: 0, notifications: 0) },
        reductionVersusBaseline: nil
    )

    var totalUnlocks: Int { hours.reduce(0) { $0 + $1.unlocks } }
    var totalNotifications: Int { hours.reduce(0) { $0 + $1.notifications } }
    var totalUsage: TimeInterval { hours.reduce(0) { $0 + $1.usage } }

    var hasAnyActivity: Bool {
        totalUsage > 0 || totalUnlocks > 0 || totalNotifications > 0
    }
}

/// Which of the three the chart is showing.
enum HourlyActivityMetric: String, CaseIterable, Identifiable, Hashable {
    case reduction
    case unlocks
    case notifications

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reduction: "Reduction"
        case .unlocks: "Unlocks"
        case .notifications: "Notifications"
        }
    }
}
