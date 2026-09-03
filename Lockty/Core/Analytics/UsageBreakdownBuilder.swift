import Foundation

/// Reads a period out of the cached day snapshots.
///
/// From the App Group rather than from Screen Time: a month is thirty-one report
/// requests, which is not a screen anybody would wait for, where thirty-one file reads
/// is a screen that opens. The cost is that a day with no cached snapshot is a day that
/// did not happen as far as this is concerned -- which is why the count of days with data
/// travels with the answer instead of being hidden inside an average.
struct UsageBreakdownBuilder {
    private let appGroupStore: AppGroupStore

    /// Below this, an app in the neutral section is folded into the stack rather than
    /// given a row. Five minutes across a whole period is a thing you opened, not a thing
    /// you did.
    private let foldThreshold: TimeInterval = 5 * 60

    init(appGroupStore: AppGroupStore = AppGroupStore()) {
        self.appGroupStore = appGroupStore
    }

    func breakdown(
        period: UsagePeriod,
        anchorDay: Date,
        classifications: [AppIdentity.ID: AppClassification],
        calendar: Calendar = .current
    ) -> UsageBreakdown {
        let days = period.days(containing: anchorDay, calendar: calendar)
        let current = totals(for: days)

        guard current.daysWithData > 0 else {
            return .empty(period: period, anchorDay: anchorDay)
        }

        // A day is a total; anything longer is a daily average. Divided by the days that
        // actually reported, not by the length of the period -- a month read on the third
        // is an average of three days, and dividing by thirty-one would quietly report a
        // fifth of the truth as an improvement.
        let headline = period == .day
            ? current.total
            : current.total / Double(current.daysWithData)

        return UsageBreakdown(
            period: period,
            anchorDay: anchorDay,
            headlineDuration: headline,
            deltaVersusPrevious: delta(
                period: period,
                anchorDay: anchorDay,
                headline: headline,
                calendar: calendar
            ),
            sections: sections(from: current.durations, classifications: classifications),
            daysWithData: current.daysWithData
        )
    }

    /// Every app seen in the last month, whether or not it was used in the period on
    /// screen.
    ///
    /// Editing is about what an app *is*, which does not change with the week you are
    /// looking at -- so a grid that only offered this week's apps would refuse to let you
    /// file the one you were thinking of. A month of cached snapshots is a month of file
    /// reads; nothing is asked of Screen Time.
    func knownApps(classifications: [AppIdentity.ID: AppClassification], calendar: Calendar = .current) -> [UsageBreakdownApp] {
        var seen: [AppIdentity.ID: UsageBreakdownApp] = [:]
        let today = calendar.startOfDay(for: Date())

        for daysBack in 0...30 {
            guard let day = calendar.date(byAdding: .day, value: -daysBack, to: today),
                  let snapshot = try? appGroupStore.loadScreenTimeReportSnapshot(for: DayKey(date: day))
            else { continue }

            for application in snapshot.applications where application.totalActivityDuration > 0 && Self.isRealApp(application.app) {
                var entry = seen[application.app.id] ?? UsageBreakdownApp(
                    app: application.app,
                    duration: 0,
                    classification: classifications[application.app.id] ?? .neutral
                )
                entry.duration += application.totalActivityDuration
                seen[application.app.id] = entry
            }
        }

        return seen.values.sorted { $0.duration > $1.duration }
    }

    /// Whether an entry is an app someone could recognise and file.
    ///
    /// Screen Time reports things that are not apps -- activity it could name but not
    /// identify, which arrives with no token and an id synthesised from a display name.
    /// Those are fine in a list of where the time went; they are not fine in a grid whose
    /// whole purpose is to say what each *app* is, because there is nothing to say it
    /// about and nothing that would remember the answer.
    private static func isRealApp(_ app: AppIdentity) -> Bool {
        if app.applicationToken != nil { return true }
        guard let bundleIdentifier = app.bundleIdentifier else { return false }
        return !bundleIdentifier.isEmpty && !bundleIdentifier.hasPrefix("display.")
    }

    // MARK: - Totals

    private func totals(for days: [Date]) -> (durations: [AppIdentity.ID: UsageBreakdownApp], total: TimeInterval, daysWithData: Int) {
        var durations: [AppIdentity.ID: UsageBreakdownApp] = [:]
        var total: TimeInterval = 0
        var daysWithData = 0

        for day in days {
            guard let snapshot = try? appGroupStore.loadScreenTimeReportSnapshot(for: DayKey(date: day)),
                  snapshot.totalActivityDuration > 0
            else { continue }

            daysWithData += 1
            total += snapshot.totalActivityDuration

            for application in snapshot.applications {
                var entry = durations[application.app.id] ?? UsageBreakdownApp(
                    app: application.app,
                    duration: 0,
                    classification: .neutral
                )
                entry.duration += application.totalActivityDuration
                durations[application.app.id] = entry
            }
        }

        return (durations, total, daysWithData)
    }

    /// How this period compares with the one immediately before it.
    ///
    /// Positive means less was used, which is the direction worth a green arrow. Nil when
    /// the previous period has no data at all: a first week has nothing to be better
    /// than, and telling someone they improved by their entire usage would be a lie
    /// dressed as encouragement.
    private func delta(
        period: UsagePeriod,
        anchorDay: Date,
        headline: TimeInterval,
        calendar: Calendar
    ) -> TimeInterval? {
        let component: Calendar.Component = switch period {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        }

        guard let previousAnchor = calendar.date(byAdding: component, value: -1, to: anchorDay) else {
            return nil
        }

        let previous = totals(for: period.days(containing: previousAnchor, calendar: calendar))
        guard previous.daysWithData > 0 else { return nil }

        let previousHeadline = period == .day
            ? previous.total
            : previous.total / Double(previous.daysWithData)

        return previousHeadline - headline
    }

    // MARK: - Sections

    private func sections(
        from durations: [AppIdentity.ID: UsageBreakdownApp],
        classifications: [AppIdentity.ID: AppClassification]
    ) -> [UsageBreakdownSection] {
        let classified = durations.values
            .filter { $0.duration > 0 }
            .map { entry -> UsageBreakdownApp in
                var entry = entry
                entry.classification = classifications[entry.app.id] ?? .neutral
                return entry
            }

        // Distracting first. It is the section people came to look at, and putting it
        // under a list of what went well is how a screen becomes reassuring instead of
        // useful.
        let order: [AppClassification] = [.unproductive, .productive, .neutral]

        return order.compactMap { classification in
            let apps = classified
                .filter { $0.classification == classification }
                .sorted { $0.duration > $1.duration }
            guard !apps.isEmpty else { return nil }

            guard classification == .neutral else {
                return UsageBreakdownSection(classification: classification, apps: apps, foldedApps: [])
            }

            let listed = apps.filter { $0.duration >= foldThreshold }
            let folded = apps.filter { $0.duration < foldThreshold }
            // Never fold the whole section away: a neutral list where everything is small
            // would collapse to a single anonymous row, which answers nothing.
            if listed.isEmpty {
                return UsageBreakdownSection(classification: classification, apps: Array(apps.prefix(3)), foldedApps: Array(apps.dropFirst(3)))
            }
            return UsageBreakdownSection(classification: classification, apps: listed, foldedApps: folded)
        }
    }
}
