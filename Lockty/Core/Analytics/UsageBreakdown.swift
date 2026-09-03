import Foundation

/// A stretch of time, and how a phone was spent across it.
nonisolated enum UsagePeriod: String, CaseIterable, Identifiable, Hashable, Sendable {
    case day
    case week
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: "Day"
        case .week: "Week"
        case .month: "Month"
        }
    }

    /// What the big figure underneath means. A day is a total; longer than that it is an
    /// average, because "42 hours" says nothing a person can act on and "6 h a day" does.
    var totalCaption: String {
        switch self {
        case .day: "Screen time"
        case .week, .month: "Average screen time"
        }
    }

    /// The days a period covers, given a day inside it.
    ///
    /// A week runs Monday to Sunday whichever day is picked -- choosing a Wednesday means
    /// the week that Wednesday is in, not the seven days ending on it. A period is a
    /// calendar thing; a rolling window is a different question.
    func days(containing day: Date, calendar: Calendar) -> [Date] {
        var calendar = calendar
        calendar.firstWeekday = 2

        let start = calendar.startOfDay(for: day)
        switch self {
        case .day:
            return [start]

        case .week:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: start) else { return [start] }
            return stride(from: 0, to: 7, by: 1).compactMap {
                calendar.date(byAdding: .day, value: $0, to: interval.start)
            }

        case .month:
            guard let interval = calendar.dateInterval(of: .month, for: start),
                  let count = calendar.dateComponents([.day], from: interval.start, to: interval.end).day
            else { return [start] }
            return stride(from: 0, to: count, by: 1).compactMap {
                calendar.date(byAdding: .day, value: $0, to: interval.start)
            }
        }
    }
}

/// One app's share of a period.
nonisolated struct UsageBreakdownApp: Identifiable, Hashable {
    var app: AppIdentity
    var duration: TimeInterval
    var classification: AppClassification

    var id: AppIdentity.ID { app.id }
}

/// The apps of one classification, and what they add up to.
nonisolated struct UsageBreakdownSection: Identifiable, Hashable {
    var classification: AppClassification
    var apps: [UsageBreakdownApp]
    /// The ones too small to be worth a row of their own, folded into one.
    ///
    /// Only ever in the neutral section. Productive and unproductive time is the point of
    /// the screen and every minute of it is worth naming; neutral is where a phone's
    /// forty-app tail lives, and a list of forty two-minute rows buries the five that
    /// matter.
    var foldedApps: [UsageBreakdownApp]

    var id: String { classification.rawValue }

    var total: TimeInterval {
        (apps + foldedApps).reduce(0) { $0 + $1.duration }
    }

    var foldedTotal: TimeInterval {
        foldedApps.reduce(0) { $0 + $1.duration }
    }

    /// The classification's own name, so this screen and the menu that changes it agree.
    var title: String {
        classification.title
    }
}

/// A period, read.
nonisolated struct UsageBreakdown: Hashable {
    var period: UsagePeriod
    /// The day the period was picked from, so the screen can say which one it is showing.
    var anchorDay: Date
    /// Per day for a week or a month, total for a day.
    var headlineDuration: TimeInterval
    /// How the period compares with the one before it. Positive is less used, which is
    /// the direction worth celebrating. Nil when there is nothing to compare against.
    var deltaVersusPrevious: TimeInterval?
    var sections: [UsageBreakdownSection]
    /// How many days in the period actually had data. A month read three days in is an
    /// average of three days, and saying so is the difference between a figure and a
    /// claim.
    var daysWithData: Int

    static func empty(period: UsagePeriod, anchorDay: Date) -> UsageBreakdown {
        UsageBreakdown(
            period: period,
            anchorDay: anchorDay,
            headlineDuration: 0,
            deltaVersusPrevious: nil,
            sections: [],
            daysWithData: 0
        )
    }

    var hasData: Bool { daysWithData > 0 }
}
